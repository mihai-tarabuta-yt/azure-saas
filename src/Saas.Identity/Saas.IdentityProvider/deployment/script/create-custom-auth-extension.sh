#!/usr/bin/env bash

set -u -e -o pipefail

# shellcheck disable=SC1091
{
    source "${ASDK_DEPLOYMENT_SCRIPT_PROJECT_BASE}/constants.sh"
    source "$SHARED_MODULE_DIR/config-module.sh"
    source "$SHARED_MODULE_DIR/app-reg-module.sh"
    source "$SHARED_MODULE_DIR/log-module.sh"
    source "$SHARED_MODULE_DIR/tenant-login-module.sh"
    source "$SHARED_MODULE_DIR/user-module.sh"
}

# Microsoft Graph's own service principal, and the fixed app role it exposes for this feature.
GRAPH_APP_ID="00000003-0000-0000-c000-000000000000"
GRAPH_RECEIVE_PAYLOAD_ROLE_ID="214e810f-fda8-4fd7-a475-29461495eb00"

# Microsoft's first-party service that calls custom authentication extensions - fixed, documented app ID.
AUTH_EXTENSIONS_CALLER_APP_ID="99045fe1-7639-4a75-9d4a-577b6ca3810f"

APP_NAME="permissions-token-extension"
CUSTOM_ROLE_VALUE="CustomAuthenticationExtension.Receive.Payload"

b2c_tenant_name="$(get-value ".deployment.azureb2c.domainName")"
b2c_config_usr_name="$(get-value ".deployment.azureb2c.username")"
set-user-context "${b2c_config_usr_name}"

echo "Logging into B2C tenant ${b2c_tenant_name}." |
    log-output \
        --level info \
        --header "Custom Authentication Extension"

log-into-b2c "${b2c_tenant_name}" ||
    echo "Azure B2C tenant login failed." |
    log-output \
        --level error \
        --header "Critical error" ||
    exit 1

app_id="$(get-value ".appRegistrations[] | select(.name==\"${APP_NAME}\") | .appId")"

if ! app-exist "${app_id}"; then
    echo "App registration for ${APP_NAME} does not exist yet. It should have already been created by b2c-app-registrations.sh - aborting." |
        log-output \
            --level error \
            --header "Critical error"
    exit 1
fi

app_obj_id="$(get-value ".appRegistrations[] | select(.name==\"${APP_NAME}\") | .objectId")"
permissions_api_base_url="$(get-value ".appRegistrations[] | select(.name==\"permissions-api\") | .baseUrl")"
target_url="${permissions_api_base_url}/api/TokenIssuanceStart"
identifier_uri="api://$(echo "${permissions_api_base_url}" | sed -E 's#^https?://##')/${app_id}"

echo "Setting identifier URI for ${APP_NAME} (must share the Permissions API's domain)..." |
    log-output --level info

az ad app update \
    --id "${app_id}" \
    --only-show-errors \
    --identifier-uris "${identifier_uri}" ||
    echo "Failed to set identifier URI for ${APP_NAME}" |
        log-output --level error --header "Critical error" ||
    exit 1

echo "Setting requestedAccessTokenVersion, custom app role, and required Graph resource access..." |
    log-output --level info

patch_body=$(cat <<EOF
{
  "api": {
    "requestedAccessTokenVersion": 2
  },
  "appRoles": [
    {
      "id": "$(get-value ".deployment.azureb2c.customAuthExtension.appRoleId" | grep -vx null || cat /proc/sys/kernel/random/uuid)",
      "allowedMemberTypes": ["Application"],
      "displayName": "Receive custom authentication extension HTTP requests",
      "description": "Allow Microsoft Entra to call this API's custom authentication extension endpoint.",
      "value": "${CUSTOM_ROLE_VALUE}",
      "isEnabled": true
    }
  ],
  "requiredResourceAccess": [
    {
      "resourceAppId": "${GRAPH_APP_ID}",
      "resourceAccess": [
        { "id": "37f7f235-527c-4136-accd-4a02d197296e", "type": "Scope" },
        { "id": "7427e0e9-2fba-42fe-b0c0-848c9e6a8182", "type": "Scope" },
        { "id": "${GRAPH_RECEIVE_PAYLOAD_ROLE_ID}", "type": "Role" }
      ]
    }
  ]
}
EOF
)

az rest --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/${app_obj_id}" \
    --headers "Content-Type=application/json" \
    --body "${patch_body}" ||
    echo "Failed to patch ${APP_NAME} api/appRoles/requiredResourceAccess" |
        log-output --level error --header "Critical error" ||
    exit 1

app_role_id="$(az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/applications/${app_obj_id}" \
    --query "appRoles[?value=='${CUSTOM_ROLE_VALUE}'].id | [0]" \
    --output tsv)"

put-value ".deployment.azureb2c.customAuthExtension.appRoleId" "${app_role_id}"

echo "Ensuring a service principal exists for ${APP_NAME}..." |
    log-output --level info

if ! az ad sp show --id "${app_id}" --only-show-errors >/dev/null 2>&1; then
    az ad sp create --id "${app_id}" --only-show-errors >/dev/null ||
        echo "Failed to create service principal for ${APP_NAME}" |
            log-output --level error --header "Critical error" ||
        exit 1
fi

app_sp_id="$(az ad sp show --id "${app_id}" --query "id" --output tsv)"

echo "Ensuring Microsoft's custom-authentication-extension caller service principal exists in this tenant..." |
    log-output --level info

first_party_sp_id="$(az ad sp show --id "${AUTH_EXTENSIONS_CALLER_APP_ID}" --query "id" --output tsv 2>/dev/null || echo "")"

if [[ -z "${first_party_sp_id}" ]]; then
    first_party_sp_id="$(az ad sp create --id "${AUTH_EXTENSIONS_CALLER_APP_ID}" --only-show-errors --query "id" --output tsv)"
fi

echo "Granting '${CUSTOM_ROLE_VALUE}' to Microsoft's caller service principal, if not already granted..." |
    log-output --level info

already_assigned="$(az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${first_party_sp_id}/appRoleAssignments" \
    --query "value[?resourceId=='${app_sp_id}' && appRoleId=='${app_role_id}'] | [0].id" \
    --output tsv)"

if [[ -z "${already_assigned}" || "${already_assigned}" == "None" ]]; then
    assignment_body=$(cat <<EOF
{
  "principalId": "${first_party_sp_id}",
  "resourceId": "${app_sp_id}",
  "appRoleId": "${app_role_id}"
}
EOF
)
    az rest --method POST \
        --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${first_party_sp_id}/appRoleAssignments" \
        --headers "Content-Type=application/json" \
        --body "${assignment_body}" >/dev/null ||
        echo "Failed to grant ${CUSTOM_ROLE_VALUE} to Microsoft's caller service principal" |
            log-output --level error --header "Critical error" ||
        exit 1
fi

put-value ".deployment.azureb2c.customAuthExtension.firstPartyServicePrincipalId" "${first_party_sp_id}"

# Separate from the grant above: this is US being granted Graph's OWN "CustomAuthenticationExtension.
# Receive.Payload" app role (requested via requiredResourceAccess earlier), not Microsoft's caller being
# granted OUR custom role. Without this, sign-in fails with AADSTS1003021 even though everything else
# is wired correctly - adding requiredResourceAccess only *requests* the permission, it doesn't consent it.
echo "Granting ourselves Microsoft Graph's '${CUSTOM_ROLE_VALUE}' role, if not already granted..." |
    log-output --level info

graph_sp_id="$(az ad sp show --id "${GRAPH_APP_ID}" --query "id" --output tsv)"

already_self_assigned="$(az rest --method GET \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${app_sp_id}/appRoleAssignments" \
    --query "value[?resourceId=='${graph_sp_id}' && appRoleId=='${GRAPH_RECEIVE_PAYLOAD_ROLE_ID}'] | [0].id" \
    --output tsv)"

if [[ -z "${already_self_assigned}" || "${already_self_assigned}" == "None" ]]; then
    self_assignment_body=$(cat <<EOF
{
  "principalId": "${app_sp_id}",
  "resourceId": "${graph_sp_id}",
  "appRoleId": "${GRAPH_RECEIVE_PAYLOAD_ROLE_ID}"
}
EOF
)
    az rest --method POST \
        --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${app_sp_id}/appRoleAssignments" \
        --headers "Content-Type=application/json" \
        --body "${self_assignment_body}" >/dev/null ||
        echo "Failed to grant ${APP_NAME} its own ${CUSTOM_ROLE_VALUE} role from Microsoft Graph" |
            log-output --level error --header "Critical error" ||
        exit 1
fi

custom_ext_id="$(get-value ".deployment.azureb2c.customAuthExtension.customAuthenticationExtensionId" | grep -vx null || echo "")"

if [[ -z "${custom_ext_id}" ]]; then
    echo "Creating the customAuthenticationExtensions resource..." |
        log-output --level info

    ext_body=$(cat <<EOF
{
  "@odata.type": "#microsoft.graph.onTokenIssuanceStartCustomExtension",
  "displayName": "${APP_NAME}",
  "description": "Fetches permissions/roles claims from the SaaS Permissions API",
  "endpointConfiguration": {
    "@odata.type": "#microsoft.graph.httpRequestEndpoint",
    "targetUrl": "${target_url}"
  },
  "authenticationConfiguration": {
    "@odata.type": "#microsoft.graph.azureAdTokenAuthentication",
    "resourceId": "${identifier_uri}"
  },
  "claimsForTokenConfiguration": [
    { "claimIdInApiResponse": "permissions" },
    { "claimIdInApiResponse": "roles" }
  ]
}
EOF
)

    custom_ext_id="$(az rest --method POST \
        --uri "https://graph.microsoft.com/beta/identity/customAuthenticationExtensions" \
        --headers "Content-Type=application/json" \
        --body "${ext_body}" \
        --query "id" \
        --output tsv)" ||
        echo "Failed to create customAuthenticationExtensions resource" |
            log-output --level error --header "Critical error" ||
        exit 1

    put-value ".deployment.azureb2c.customAuthExtension.customAuthenticationExtensionId" "${custom_ext_id}"
else
    echo "customAuthenticationExtensions resource already exists (${custom_ext_id}), skipping creation." |
        log-output --level info
fi

listener_id="$(get-value ".deployment.azureb2c.customAuthExtension.authenticationEventListenerId" | grep -vx null || echo "")"

saas_app_appid="$(get-value ".appRegistrations[] | select(.name==\"saas-app\") | .appId")"
admin_api_appid="$(get-value ".appRegistrations[] | select(.name==\"admin-api\") | .appId")"

if [[ -z "${listener_id}" ]]; then
    echo "Creating the authenticationEventListener for saas-app and admin-api..." |
        log-output --level info

    # Both the client app (saas-app, which triggers sign-in and receives the id_token) and the
    # resource app (admin-api, the audience of the access token saas-app acquires to call it) must be
    # listed here - confirmed live: with only saas-app listed, saas-app's id_token got the "permissions"
    # claim but the access token issued for admin-api's audience did not, even with a claims mapping
    # policy assigned to admin-api's own service principal. Listing admin-api here too is what made the
    # access token get enriched.
    listener_body=$(cat <<EOF
{
  "@odata.type": "#microsoft.graph.onTokenIssuanceStartListener",
  "conditions": {
    "applications": {
      "includeAllApplications": false,
      "includeApplications": [
        { "appId": "${saas_app_appid}" },
        { "appId": "${admin_api_appid}" }
      ]
    }
  },
  "priority": 500,
  "handler": {
    "@odata.type": "#microsoft.graph.onTokenIssuanceStartCustomExtensionHandler",
    "customExtension": {
      "id": "${custom_ext_id}"
    }
  }
}
EOF
)

    listener_id="$(az rest --method POST \
        --uri "https://graph.microsoft.com/beta/identity/authenticationEventListeners" \
        --headers "Content-Type=application/json" \
        --body "${listener_body}" \
        --query "id" \
        --output tsv)" ||
        echo "Failed to create authenticationEventListener" |
            log-output --level error --header "Critical error" ||
        exit 1

    put-value ".deployment.azureb2c.customAuthExtension.authenticationEventListenerId" "${listener_id}"
else
    echo "authenticationEventListener already exists (${listener_id}), skipping creation." |
        log-output --level info
fi

# Enable claims mapping for both the client app (saas-app, gets the claim in its ID token) and the
# resource app (admin-api, gets the claim in access tokens issued for it) - per Microsoft's docs, a
# claims mapping policy must be assigned to the client app's service principal for ID token claims, and
# separately to the resource app's service principal for access token claims. Confirmed live both are
# required; skipping either leaves that token type without the "permissions"/"roles" claims.
claims_policy_id="$(get-value ".deployment.azureb2c.customAuthExtension.claimsMappingPolicyId" | grep -vx null || echo "")"

if [[ -z "${claims_policy_id}" ]]; then
    echo "Creating the claims mapping policy for permissions/roles..." |
        log-output --level info

    policy_definition='{"ClaimsMappingPolicy":{"Version":1,"IncludeBasicClaimSet":"true","ClaimsSchema":[{"Source":"CustomClaimsProvider","ID":"permissions","JwtClaimType":"permissions"},{"Source":"CustomClaimsProvider","ID":"roles","JwtClaimType":"roles"}]}}'
    escaped_definition="$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$policy_definition")"
    policy_body="{\"definition\":[${escaped_definition}],\"displayName\":\"SaasAppPermissionsClaimsMappingPolicy\",\"isOrganizationDefault\":false}"

    claims_policy_id="$(az rest --method POST \
        --uri "https://graph.microsoft.com/v1.0/policies/claimsMappingPolicies" \
        --headers "Content-Type=application/json" \
        --body "${policy_body}" \
        --query "id" \
        --output tsv)" ||
        echo "Failed to create claims mapping policy" |
            log-output --level error --header "Critical error" ||
        exit 1

    put-value ".deployment.azureb2c.customAuthExtension.claimsMappingPolicyId" "${claims_policy_id}"
else
    echo "Claims mapping policy already exists (${claims_policy_id}), skipping creation." |
        log-output --level info
fi

for claims_target_app_name in "saas-app" "admin-api"; do
    target_appid="$(get-value ".appRegistrations[] | select(.name==\"${claims_target_app_name}\") | .appId")"
    target_obj_id="$(get-value ".appRegistrations[] | select(.name==\"${claims_target_app_name}\") | .objectId")"

    echo "Enabling acceptMappedClaims on ${claims_target_app_name}..." |
        log-output --level info

    az rest --method PATCH \
        --uri "https://graph.microsoft.com/v1.0/applications/${target_obj_id}" \
        --headers "Content-Type=application/json" \
        --body '{"api":{"acceptMappedClaims":true,"requestedAccessTokenVersion":2}}' ||
        echo "Failed to enable acceptMappedClaims on ${claims_target_app_name}" |
            log-output --level error --header "Critical error" ||
        exit 1

    target_sp_id="$(az ad sp show --id "${target_appid}" --query "id" --output tsv)"

    already_has_policy="$(az rest --method GET \
        --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${target_sp_id}/claimsMappingPolicies" \
        --query "value[?id=='${claims_policy_id}'] | [0].id" \
        --output tsv)"

    if [[ -z "${already_has_policy}" || "${already_has_policy}" == "None" ]]; then
        echo "Assigning claims mapping policy to ${claims_target_app_name}'s service principal..." |
            log-output --level info

        az rest --method POST \
            --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${target_sp_id}/claimsMappingPolicies/\$ref" \
            --headers "Content-Type=application/json" \
            --body "{\"@odata.id\":\"https://graph.microsoft.com/v1.0/policies/claimsMappingPolicies/${claims_policy_id}\"}" ||
            echo "Failed to assign claims mapping policy to ${claims_target_app_name}" |
                log-output --level error --header "Critical error" ||
            exit 1
    else
        echo "Claims mapping policy already assigned to ${claims_target_app_name}, skipping." |
            log-output --level info
    fi
done

reset-user-context

echo "Custom authentication extension is fully provisioned." |
    log-output --level success
