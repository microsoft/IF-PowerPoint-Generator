using PptGenerator.Web.Models;

namespace PptGenerator.Web.Services;

public interface IOrchestratorService
{
    Task<JobSubmitResponse> SubmitJobAsync(string jsonPayload);
    Task<JobStatus?> GetStatusAsync(string jobId);
    bool IsAvailable { get; }
}
