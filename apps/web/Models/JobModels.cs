using Newtonsoft.Json;

namespace PptGenerator.Web.Models;

public class JobSubmitRequest
{
    [JsonProperty("json_content")]
    public string JsonContent { get; set; } = string.Empty;
}

public class JobSubmitResponse
{
    [JsonProperty("jobId")]  // Functions API returns camelCase
    public string JobId { get; set; } = string.Empty;

    [JsonProperty("status")]
    public string Status { get; set; } = string.Empty;

    [JsonProperty("message")]
    public string? Message { get; set; }

    [JsonProperty("error")]
    public string? Error { get; set; }

    [JsonProperty("statusUrl")]
    public string? StatusUrl { get; set; }
}

public class JobStatus
{
    [JsonProperty("id")]
    public string Id { get; set; } = string.Empty;

    [JsonProperty("jobId")]  // Functions API returns camelCase
    public string JobId { get; set; } = string.Empty;

    [JsonProperty("status")]
    public string Status { get; set; } = "pending";

    [JsonProperty("progress")]
    public int Progress { get; set; }

    [JsonProperty("stage")]  // Functions API uses "stage" not "current_step"
    public string? CurrentStep { get; set; }

    [JsonProperty("downloadUrl")]  // Functions API uses camelCase
    public string? OutputUrl { get; set; }

    [JsonProperty("error")]
    public string? Error { get; set; }

    [JsonProperty("startedAt")]
    public DateTime? StartedAt { get; set; }

    [JsonProperty("completedAt")]
    public DateTime? CompletedAt { get; set; }

    [JsonProperty("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [JsonProperty("payload")]
    public object? Payload { get; set; }

    [JsonProperty("simulated")]
    public bool Simulated { get; set; }
}

public class SamplePayload
{
    public string Filename { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string SourceType { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
}

public class ErrorViewModel
{
    public string? RequestId { get; set; }
    public bool ShowRequestId => !string.IsNullOrEmpty(RequestId);
    public string? Message { get; set; }
}
