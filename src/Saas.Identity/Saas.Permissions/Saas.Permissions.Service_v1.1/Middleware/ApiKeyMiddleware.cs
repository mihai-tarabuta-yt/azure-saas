using Microsoft.Extensions.Options;
using Saas.Permissions.Service.Models;
using Saas.Shared.Options;

namespace Saas.Permissions.Service.Middleware;

public class ApiKeyMiddleware(IOptions<PermissionsApiOptions> permissionOptions, RequestDelegate next)
{    
    private readonly RequestDelegate _next = next;
    private const string API_KEY = "x-api-key";
    private readonly PermissionsApiOptions _permissionOptions = permissionOptions.Value;

    public async Task InvokeAsync(HttpContext context) {

        // Microsoft's custom authentication extension caller sends a bearer token, not x-api-key -
        // that route is authorized separately via the "TokenIssuanceStart" scheme (see Program.cs).
        if (context.Request.Path.StartsWithSegments("/api/TokenIssuanceStart", StringComparison.OrdinalIgnoreCase))
        {
            await _next(context);
            return;
        }

        if (!context.Request.Headers.TryGetValue(API_KEY, out var extractedApiKey)) {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new UnauthorizedResponse($"API Key must be provided on the {API_KEY} header"));
            return;
        }
        
        var appSettings = context.RequestServices.GetRequiredService<IConfiguration>();
        
        var apiKey = _permissionOptions.ApiKey
                ?? throw new NullReferenceException("API Key cannot be null.");

        if (!apiKey.Equals(extractedApiKey, StringComparison.Ordinal))
        {
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new UnauthorizedResponse("API Key provided was invalid."));
            return;
        }
        
        await _next(context);
    }
}