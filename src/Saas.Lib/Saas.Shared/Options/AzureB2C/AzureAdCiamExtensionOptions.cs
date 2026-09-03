namespace Saas.Shared.Options;

// Config for validating inbound bearer tokens from Microsoft Entra's custom authentication extension
// caller (see Saas.Permissions.Service's TokenIssuanceStartController) - not an outbound client, so
// only the values needed for JWT bearer validation (Instance/TenantId/ClientId) are present.
public record AzureAdCiamExtensionOptions : AzureAdB2CBase
{
    public const string SectionName = "PermissionsApi:AzureAdCiamExtension";
}
