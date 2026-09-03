#!/usr/bin/env bash

# shellcheck disable=SC1091
# loading modules into current shell
source "$SHARED_MODULE_DIR/config-module.sh"
source "$SHARED_MODULE_DIR/user-module.sh"
source "$SHARED_MODULE_DIR/log-module.sh"

function service-principal-exist-by-id() {
    local service_principal_id="$1"

    if [[ -z "${service_principal_id}" \
        || "${service_principal_id}" == null \
        || "${service_principal_id}" == "null" ]]; then

        false
        return
    fi

    service_principal_response="$( az ad sp show \
        --id "${service_principal_id}" \
        --query id \
        --output tsv )"

    if [[ -n "${service_principal_response}" ]]; then
        true
        return
    else
        false
        return
    fi
}

function delete-service-principal-credentials() {
    local app_id="$1"

    if [[ -z "${app_id}" || "${app_id}" == "null" ]]; then
        echo "No known service principal to delete." \
            | log-output \
                --level info
        return
    fi

    echo "Deleting service principal credentials for ${app_id}." \
        | log-output \
            --level info

    key_ids="$( az ad sp show \
        --id "${app_id}"\
        --query "keyCredentials" 2> /dev/null \
        || echo "Unable to delete service principal for ${app_id}, please delete it manually." \
            | log-output \
                --level warning )"

    # iterate over each key_id into an array
    readarray -t key_ids_array< <( jq --compact-output '.[]' <<< "${key_ids}" )

    if [[ "${#key_ids_array[@]}" -eq 0 ]]; then
        echo "No service principal credentials to delete." \
            | log-output \
                --level info
        return
    else
        principal_object_id="$( az ad sp show \
            --id "${app_id}" \
            --query "id" \
            --output tsv  )" \
            || echo "Failed to get service principal object id for appId ${app_id}" \
                | log-output \
                    --level warning \
                    --header "Warning!"
    fi

    # delete all service principal credentials
    for key_ids_array in "${key_ids_array[@]}"; do
        key_id="$( jq --raw-output '.keyId' <<< "${key_ids_array}" )"

        echo "Deleting service principal credentials with keyId: ${key_id} for ${principal_object_id}..." \
            | log-output --level info

        az ad sp credential delete \
            --id "${principal_object_id}" \
            --key-id "${key_id}" \
            --cert \
            | log-output \
            || echo "Failed to delete service principal credentials with keyId ${key_id} for appId ${app_id}. $?" \
                | log-output \
                    --level warning \
                    --header "Warning!"
    done
}


