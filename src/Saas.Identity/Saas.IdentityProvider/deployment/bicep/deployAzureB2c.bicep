
param location string
param countryCode string
param displayName string
param name string
param skuName string
param tier string
// Required by the live API for 'GoLocal-enabled' countries (e.g. AU, JP) - whether to use
// the GoLocal add-on (data stored exclusively in-country) vs. the standard regional pool.
param isGoLocalTenant bool = false

// Azure AD B2C is closed to new tenant creation (no existing b2cDirectories in this
// subscription/tenant can no longer be provisioned). This deploys a Microsoft Entra
// External ID (CIAM) tenant instead - the supported successor for new deployments.
// Note: 'location' must be one of 'United States' | 'Europe' | 'Asia Pacific' | 'Australia'.
// 'skuName' must be 'Base' (Microsoft's published schema docs list PremiumP1/PremiumP2/Standard,
// but the live API rejects those for ciamDirectories and requires 'Base', tier 'A0').
// Pinned to api-version 2025-08-01-preview deliberately: 2023-05-17-preview (what Microsoft's
// own docs/bicep type index still describe) has a live bug for GoLocal countries (AU, JP) where
// isGoLocalTenant is simultaneously required and rejected - confirmed broken via direct REST
// testing. 2025-08-01-preview (found via `az provider show`, undocumented) works correctly.
resource ciamDirectory 'Microsoft.AzureActiveDirectory/ciamDirectories@2025-08-01-preview' = {
  name: name
  location: location
  sku: {
    name: skuName
    tier: tier
  }
  properties: {
    createTenantProperties: {
      countryCode: countryCode
      displayName: displayName
      isGoLocalTenant: isGoLocalTenant
    }
  }
}

output tenantId string = ciamDirectory.properties.tenantId
