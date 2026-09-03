using Microsoft.AspNetCore.Authorization;
using Saas.Permissions.Service.Interfaces;
using Saas.Permissions.Service.Models;

namespace Saas.Permissions.Service.Controllers;

// Replaces IEF's REST-GetPermissions/REST-GetRoles technical profiles: Microsoft Entra (CIAM) calls
// this endpoint via a custom authentication extension on the onTokenIssuanceStart event, instead of
// the old raw x-api-key REST callout. Authenticated with a Microsoft-issued bearer token (validated
// against the "permissions-token-extension" app registration), not the shared x-api-key - see the
// "TokenIssuanceStart" auth scheme in Program.cs and the bypass in ApiKeyMiddleware.
[Route("api/[controller]")]
[ApiController]
[Authorize(AuthenticationSchemes = "TokenIssuanceStart")]
public class TokenIssuanceStartController(IPermissionsService permissionsService, ILogger<TokenIssuanceStartController> logger) : ControllerBase
{
    private readonly IPermissionsService _permissionsService = permissionsService;
    private readonly ILogger _logger = logger;

    [HttpPost]
    [Produces("application/json")]
    [ProducesResponseType(typeof(TokenIssuanceStartResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> Post(TokenIssuanceStartRequest request)
    {
        var objectId = request.Data?.AuthenticationContext?.User?.Id ?? Guid.Empty;

        _logger.LogDebug("Token issuance start callout for user id: {objectId}", objectId);

        var permissions = await _permissionsService.GetPermissionsAsync(objectId);

        IEnumerable<string> permissionClaims = new List<string>();

        foreach (var permission in permissions)
        {
            if (permission.UserPermissions?.Any() ?? false)
            {
                permissionClaims = permissionClaims
                    .Concat(permissions.SelectMany(permission => permission.UserPermissions)
                        .Select(user => user.ToClaim()));
            }

            if (permission.TenantPermissions?.Any() ?? false)
            {
                permissionClaims = permissionClaims
                    .Concat(permissions.SelectMany(permission => permission.TenantPermissions)
                        .Select(tenant => tenant.ToClaim()));
            }
        }

        // Roles are intentionally left empty for now, matching CustomClaimsController's existing
        // behavior - the MS Graph app-role lookup is expensive and not needed yet (see that controller).
        TokenIssuanceStartResponse response = new()
        {
            Data = new TokenIssuanceStartResponseData
            {
                Actions =
                [
                    new TokenIssuanceStartAction
                    {
                        Claims = new Dictionary<string, object>
                        {
                            ["permissions"] = permissionClaims.ToArray(),
                            ["roles"] = Array.Empty<string>(),
                        }
                    }
                ]
            }
        };

        return Ok(response);
    }
}
