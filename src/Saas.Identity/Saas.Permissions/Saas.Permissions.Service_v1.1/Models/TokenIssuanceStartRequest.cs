using System.Text.Json.Serialization;

namespace Saas.Permissions.Service.Models;

// Matches the CIAM custom authentication extension "onTokenIssuanceStart" callout contract:
// https://learn.microsoft.com/en-us/entra/identity-platform/custom-claims-provider-reference
public record TokenIssuanceStartRequest
{
    public string? Type { get; init; }

    public string? Source { get; init; }

    public TokenIssuanceStartData? Data { get; init; }
}

public record TokenIssuanceStartData
{
    [JsonPropertyName("tenantId")]
    public string? TenantId { get; init; }

    public AuthenticationContext? AuthenticationContext { get; init; }
}

public record AuthenticationContext
{
    public string? CorrelationId { get; init; }

    public ServicePrincipalContext? ClientServicePrincipal { get; init; }

    public UserContext? User { get; init; }
}

public record ServicePrincipalContext
{
    public string? Id { get; init; }

    public string? AppId { get; init; }
}

public record UserContext
{
    public Guid Id { get; init; }

    public string? Mail { get; init; }

    public string? UserPrincipalName { get; init; }
}
