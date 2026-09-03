
namespace Saas.Shared.Options;

// "AzureB2C" naming is deprecated/legacy (now configures CIAM) - see AzureAdB2CBase.cs.
public record AzureB2CSaasAppOptions : AzureAdB2CBase
{
    public const string SectionName = "SaasApp:AzureB2C";
}
