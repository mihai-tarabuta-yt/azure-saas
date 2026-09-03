using System.ComponentModel.DataAnnotations;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.Identity.Web;

namespace Saas.Application.Web.Pages.Profile;

[Authorize]
public class EditModel(ITokenAcquisition tokenAcquisition, IHttpClientFactory httpClientFactory, ILogger<EditModel> logger) : PageModel
{
    private static readonly string[] GraphScopes = ["https://graph.microsoft.com/User.ReadWrite"];

    private readonly ITokenAcquisition _tokenAcquisition = tokenAcquisition;
    private readonly IHttpClientFactory _httpClientFactory = httpClientFactory;
    private readonly ILogger<EditModel> _logger = logger;

    [BindProperty]
    public InputModel Input { get; set; } = new();

    public bool SaveSucceeded { get; private set; }
    public string? ErrorMessage { get; private set; }

    public async Task<IActionResult> OnGetAsync()
    {
        try
        {
            using var client = await CreateGraphClientAsync();
            var me = await client.GetFromJsonAsync<GraphUser>("https://graph.microsoft.com/v1.0/me?$select=displayName");

            Input.DisplayName = me?.DisplayName ?? string.Empty;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to load profile from Microsoft Graph.");
            ErrorMessage = "We couldn't load your profile right now. Please try again later.";
        }

        return Page();
    }

    public async Task<IActionResult> OnPostAsync()
    {
        if (!ModelState.IsValid)
        {
            return Page();
        }

        try
        {
            using var client = await CreateGraphClientAsync();
            var response = await client.PatchAsJsonAsync(
                "https://graph.microsoft.com/v1.0/me",
                new GraphUser { DisplayName = Input.DisplayName });

            response.EnsureSuccessStatusCode();
            SaveSucceeded = true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to update profile via Microsoft Graph.");
            ErrorMessage = "We couldn't save your profile changes right now. Please try again later.";
        }

        return Page();
    }

    private async Task<HttpClient> CreateGraphClientAsync()
    {
        var accessToken = await _tokenAcquisition.GetAccessTokenForUserAsync(GraphScopes);

        var client = _httpClientFactory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);

        return client;
    }

    public class InputModel
    {
        [Required]
        [Display(Name = "Display name")]
        public string DisplayName { get; set; } = string.Empty;
    }

    private class GraphUser
    {
        [JsonPropertyName("displayName")]
        public string? DisplayName { get; set; }
    }
}
