using System.Text;
using Newtonsoft.Json;
using PptGenerator.Web.Models;

namespace PptGenerator.Web.Services;

public class OrchestratorService : IOrchestratorService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<OrchestratorService> _logger;
    private bool _isAvailable = true;

    public bool IsAvailable => _isAvailable;

    public OrchestratorService(HttpClient httpClient, ILogger<OrchestratorService> logger)
    {
        _httpClient = httpClient;
        _logger = logger;
    }

    public async Task<JobSubmitResponse> SubmitJobAsync(string jsonPayload)
    {
        try
        {
            _logger.LogInformation("Calling orchestrator at: {BaseUrl}presentations/generate", _httpClient.BaseAddress);
            var content = new StringContent(jsonPayload, Encoding.UTF8, "application/json");
            var response = await _httpClient.PostAsync("presentations/generate", content);
            var responseContent = await response.Content.ReadAsStringAsync();
            _logger.LogInformation("Orchestrator response: {StatusCode} - {Content}", response.StatusCode, responseContent);

            if (response.IsSuccessStatusCode)
            {
                var result = JsonConvert.DeserializeObject<JobSubmitResponse>(responseContent);
                _isAvailable = true;
                return result ?? new JobSubmitResponse { Status = "error", Error = "Invalid response" };
            }

            return new JobSubmitResponse
            {
                Status = "error",
                Error = $"API returned {response.StatusCode}: {responseContent}"
            };
        }
        catch (HttpRequestException ex)
        {
            _logger.LogWarning(ex, "Orchestrator not available");
            _isAvailable = false;
            throw;
        }
        catch (TaskCanceledException ex)
        {
            _logger.LogWarning(ex, "Request to orchestrator timed out");
            _isAvailable = false;
            throw;
        }
    }

    public async Task<JobStatus?> GetStatusAsync(string jobId)
    {
        try
        {
            var response = await _httpClient.GetAsync($"presentations/status/{jobId}");

            if (response.IsSuccessStatusCode)
            {
                var content = await response.Content.ReadAsStringAsync();
                _isAvailable = true;
                return JsonConvert.DeserializeObject<JobStatus>(content);
            }

            if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                return null;
            }

            return null;
        }
        catch (HttpRequestException)
        {
            _isAvailable = false;
            return null;
        }
        catch (TaskCanceledException)
        {
            _isAvailable = false;
            return null;
        }
    }
}
