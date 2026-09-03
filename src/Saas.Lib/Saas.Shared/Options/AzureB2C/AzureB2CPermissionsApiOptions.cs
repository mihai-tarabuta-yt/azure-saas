
namespace Saas.Shared.Options;

// "AzureB2C" naming is deprecated/legacy (now configures CIAM) - see AzureAdB2CBase.cs.
public record AzureB2CPermissionsApiOptions : AzureAdB2CBase
{
    public const string SectionName = "PermissionsApi:AzureB2C";
}
