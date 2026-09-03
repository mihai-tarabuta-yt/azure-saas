#!/usr/bin/env bash

# DEPRECATED NAMING: despite the "b2c" filename/variable names (kept for compatibility with
# already-provisioned environments' config.json), this provisions a Microsoft Entra External
# ID (CIAM) directory, not an Azure AD B2C one - see the resource block below and ../../readme.md's
# "Terminology" note.

set -u -e -o pipefail

# shellcheck disable=SC1091
{
    # include script modules into current shell
    source "${ASDK_DEPLOYMENT_SCRIPT_PROJECT_BASE}/constants.sh"
    source "$SHARED_MODULE_DIR/config-module.sh"
    source "$SHARED_MODULE_DIR/resource-module.sh"
    source "$SHARED_MODULE_DIR/log-module.sh"
}

resource_group="$(get-value ".deployment.resourceGroup.name")"

b2c_location="$(get-value ".initConfig.azureb2c.location")"
b2c_country_code="$(get-value ".initConfig.azureb2c.countryCode")"
b2c_sku_name="$(get-value ".initConfig.azureb2c.skuName")"
b2c_tier="$(get-value ".initConfig.azureb2c.tier")"
# Required for 'GoLocal-enabled' countries (e.g. AU, JP) when 'location' is set to that
# country's own name rather than its broader region (e.g. 'Australia' vs 'Asia Pacific').
b2c_is_go_local_tenant="$(get-value ".initConfig.azureb2c.isGoLocalTenant")"
if [[ "${b2c_is_go_local_tenant}" != "true" ]]; then
    b2c_is_go_local_tenant="false"
fi

b2c_display_name="$(get-value ".deployment.azureb2c.displayName")"
# ciamDirectories requires a bare alphanumeric resource name (max 26 chars),
# unlike b2cDirectories which used the full '{name}.onmicrosoft.com' domain.
b2c_name="$(get-value ".deployment.azureb2c.name")"

b2c_type_name="Microsoft.AzureActiveDirectory/ciamDirectories"

if ! resource-exist "${b2c_type_name}" "${b2c_name}"; then
    echo "No CIAM (Entra External ID) directory found." |
        log-output \
            --level info
    echo "Deploying Microsoft Entra External ID (CIAM) Directory using bicep..." |
        log-output \
            --level info

    az deployment group create \
        --resource-group "${resource_group}" \
        --template-file "${BICEP_DIR}/deployAzureB2c.bicep" \
        --output none \
        --parameters \
        location="${b2c_location}" \
        countryCode="${b2c_country_code}" \
        displayName="${b2c_display_name}" \
        name="${b2c_name}" \
        skuName="${b2c_sku_name}" \
        tier="${b2c_tier}" \
        isGoLocalTenant="${b2c_is_go_local_tenant}" ||
        echo "Microsoft Entra External ID (CIAM) deployment failed." |
        log-output \
            --level error \
            --header "Critical error" ||
        exit 1

    echo "Provisionning of Microsoft Entra External ID (CIAM) tenant Successful." |
        log-output \
            --level success

    exit 0

else
    echo "Existing Microsoft Entra External ID (CIAM) tenant found and will be used." |
        log-output \
            --level success
fi
