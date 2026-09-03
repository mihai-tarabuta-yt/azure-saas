using Saas.Interface;

namespace Saas.Shared.Options;

// DEPRECATED NAMING: this project originally authenticated end users via Azure AD B2C. It has
// since migrated to Microsoft Entra External ID (CIAM) - see the migration commits starting
// 6907e30 and the "Terminology" note in src/Saas.Identity/Saas.IdentityProvider/readme.md.
// "AzureB2C"/"B2C" identifiers below (this base record, its subclasses in this folder, the
// matching "AzureB2C" App Configuration section names, and the "azureb2c" deployment config
// key) are kept unrenamed on purpose - they're load-bearing for already-provisioned
// environments' config.json/App Configuration - but they now describe the CIAM tenant, not a
// B2C one. Treat "AzureB2C" as legacy/deprecated terminology, not a literal B2C reference.
// AzureAdCiamExtensionOptions.cs (added during the migration) uses correct CIAM-based naming -
// prefer that pattern for any new options class.
public record AzureAdB2CBase
{
    public string? ClientId { get; init; }
    public string? Audience { get; init; }
    public string? Domain { get; init; }
    public string? Instance { get; init; }
    public string? SignedOutCallbackPath { get; init; }
    public string? SignUpSignInPolicyId { get; init; }
    public string? TenantId { get; init; }
    public string? LoginEndpoint { get; init; }
    public string? BaseUrl { get; init; }
    public string? Certificate { get; init; }
    public string? ClientSecret { get; init; }

    public KeyVaultCertificate[]? KeyVaultCertificateReferences { get; init; }
}
    

public record KeyVaultCertificate : IKeyVaultInfo
{
    public string? SourceType { get; init; }
    public string? KeyVaultUrl { get; init; }
    public string? KeyVaultCertificateName { get; init; }
}