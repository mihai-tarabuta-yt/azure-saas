using System.Text.Json.Serialization;

namespace Saas.Permissions.Service.Models;

// Matches the CIAM custom authentication extension "onTokenIssuanceStart" response contract:
// https://learn.microsoft.com/en-us/entra/identity-platform/custom-claims-provider-reference
public record TokenIssuanceStartResponse
{
    public TokenIssuanceStartResponseData Data { get; init; } = new();
}

public record TokenIssuanceStartResponseData
{
    [JsonPropertyName("@odata.type")]
    public string ODataType { get; init; } = "microsoft.graph.onTokenIssuanceStartResponseData";

    public TokenIssuanceStartAction[] Actions { get; init; } = [];
}

public record TokenIssuanceStartAction
{
    [JsonPropertyName("@odata.type")]
    public string ODataType { get; init; } = "microsoft.graph.tokenIssuanceStart.provideClaimsForToken";

    public Dictionary<string, object> Claims { get; init; } = [];
}
