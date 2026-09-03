#!/usr/bin/env bash

# DEPRECATED NAMING: "B2C" here is legacy - this configures app registrations in the CIAM
# tenant, not an Azure AD B2C tenant. See ../../readme.md's "Terminology" note. Kept unrenamed
# for compatibility with already-provisioned environments' config.json.

set -u -e -o pipefail

# shellcheck disable=SC1091
{
    # include script modules into current shell
    source "${ASDK_DEPLOYMENT_SCRIPT_PROJECT_BASE}/constants.sh"
    source "$SHARED_MODULE_DIR/config-module.sh"
    source "$SHARED_MODULE_DIR/colors-module.sh"
    source "$SHARED_MODULE_DIR/log-module.sh"
    source "$SHARED_MODULE_DIR/user-module.sh"
}

# setting user context to the user that will be used to configure Azure B2C
b2c_config_usr_name="$(get-value ".deployment.azureb2c.username")"
set-user-context "${b2c_config_usr_name}"

# run the shell script for provisioning the Azure B2C app registrations
"${SCRIPT_DIR}/b2c-app-registrations.sh" ||
    echo "Azure B2C app registrations failed." |
    log-output \
        --level Error \
        --header "Critical Error" ||
    exit 1

echo "Azure B2C app registrations have completed." |
    log-output \
        --level success

# resetting user context to the default User
reset-user-context

echo "Adding secrets to KeyVault" |
    log-output \
        --level info

key_vault_name="$(get-value ".deployment.keyVault.name")"

# read each item in the JSON array to an item in the Bash array
readarray -t app_reg_array < <(jq --compact-output '.appRegistrations[]' "${CONFIG_FILE}")

for app in "${app_reg_array[@]}"; do
    has_secret=$(jq --raw-output '.hasSecret' <<<"${app}")

    if [[ "${has_secret}" == true || "${has_secret}" == "true" ]]; then
        app_name=$(jq --raw-output '.name' <<<"${app}")
        secret_path=$(jq --raw-output '.secretPath' <<< "${app}")

        if [[ -s "${secret_path}" ]]; then

            secret=$(cat "${secret_path}")

            echo "Adding secret for ${app_name} to KeyVault" |
                log-output \
                    --level info

            az keyvault secret set \
                --name "${app_name}" \
                --vault-name "${key_vault_name}" \
                --value "${secret}" \
                >/dev/null ||
                echo "Failed to set new secret for ${app_name}" |
                log-output \
                    --level error \
                    --header "Critical Error" ||
                exit 1

            echo "Secret for ${app_name} added to KeyVault" |
                log-output \
                    --level success

            rm -rf "${secret_path}" || echo "Failed to clean-up/remove secret file ${secret_path}" |
                log-output \
                    --level error \
                    --header "Critical Error" ||
                exit 1
        else
            echo "Secret for ${app_name} is empty. If the secret have already been defined then this is to be expected." |
                log-output \
                    --level info
        fi
    fi
done

