

namespace Saas.Shared.Options;

// "AzureB2C" naming is deprecated/legacy (now configures CIAM) - see AzureAdB2CBase.cs.
public record AzureB2CSignupAdminOptions : AzureAdB2CBase
{
    public const string SectionName = "SignupAdmin:AzureB2C";
}
