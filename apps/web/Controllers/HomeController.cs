using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using PptGenerator.Web.Models;
using PptGenerator.Web.Services;

namespace PptGenerator.Web.Controllers;

public class HomeController : Controller
{
    private readonly ILogger<HomeController> _logger;
    private readonly IOrchestratorService _orchestratorService;
    private readonly IJobStorageService _jobStorage;
    private readonly ISampleService _sampleService;
    private readonly IConfiguration _configuration;

    private static readonly string[] ProcessingSteps =
    {
        "context_interpreter",
        "data_classifier",
        "narrative_architect",
        "template_selector",
        "visualization_strategist",
        "content_generator",
        "slide_builder",
        "quality_validator"
    };

    public HomeController(
        ILogger<HomeController> logger,
        IOrchestratorService orchestratorService,
        IJobStorageService jobStorage,
        ISampleService sampleService,
        IConfiguration configuration)
    {
        _logger = logger;
        _orchestratorService = orchestratorService;
        _jobStorage = jobStorage;
        _sampleService = sampleService;
        _configuration = configuration;
    }

    public IActionResult Index()
    {
        ViewBag.OrchestratorUrl = _configuration["Orchestrator:BaseUrl"];
        return View();
    }

    [HttpPost]
    public async Task<IActionResult> Submit([FromForm] string jsonContent)
    {
        if (string.IsNullOrWhiteSpace(jsonContent))
        {
            return Json(new JobSubmitResponse { Status = "error", Error = "JSON content is required" });
        }

        // Validate JSON
        JObject payload;
        try
        {
            payload = JObject.Parse(jsonContent);
        }
        catch (JsonException ex)
        {
            return Json(new JobSubmitResponse { Status = "error", Error = $"Invalid JSON: {ex.Message}" });
        }

        // Ensure request_id exists
        var requestId = payload["request_id"]?.ToString();
        if (string.IsNullOrEmpty(requestId))
        {
            requestId = Guid.NewGuid().ToString();
            payload["request_id"] = requestId;
        }

        // Create job record
        var job = new JobStatus
        {
            Id = requestId,
            JobId = requestId,
            Status = "submitting",
            Payload = payload,
            CreatedAt = DateTime.UtcNow
        };

        _jobStorage.SaveJob(job);

        // Try to submit to orchestrator
        try
        {
            var result = await _orchestratorService.SubmitJobAsync(payload.ToString());
            job.Status = result.Status;
            job.JobId = result.JobId ?? requestId;
            _jobStorage.UpdateJob(job);

            return Json(new JobSubmitResponse
            {
                JobId = job.JobId,
                Status = job.Status,
                Message = "Job submitted successfully",
                Error = result.Error,
                StatusUrl = result.StatusUrl
            });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Orchestrator not available, running in demo mode");

            // Demo mode - simulate submission
            job.Status = "queued";
            job.Simulated = true;
            _jobStorage.UpdateJob(job);

            return Json(new JobSubmitResponse
            {
                JobId = job.JobId,
                Status = "queued",
                Message = "Job submitted (demo mode - orchestrator not available)"
            });
        }
    }

    [HttpGet]
    public async Task<IActionResult> Status(string id)
    {
        if (string.IsNullOrEmpty(id))
        {
            return Json(new { error = "Job ID is required" });
        }

        // Check local storage first
        var job = _jobStorage.GetJob(id);

        if (job != null && job.Simulated)
        {
            // Simulate progress for demo mode
            SimulateProgress(job);
            _jobStorage.UpdateJob(job);
            return Json(job);
        }

        // Try to get from orchestrator
        var status = await _orchestratorService.GetStatusAsync(id);

        if (status != null)
        {
            if (job != null)
            {
                // Update local cache
                job.Status = status.Status;
                job.Progress = status.Progress;
                job.CurrentStep = status.CurrentStep;
                job.OutputUrl = status.OutputUrl;
                job.Error = status.Error;
                _jobStorage.UpdateJob(job);
            }
            return Json(status);
        }

        // Return local job if available
        if (job != null)
        {
            return Json(job);
        }

        return NotFound(new { error = "Job not found" });
    }

    private void SimulateProgress(JobStatus job)
    {
        if (job.Status == "completed" || job.Status == "error")
            return;

        var currentProgress = job.Progress;
        var stepIndex = currentProgress / 12; // 8 steps, ~12% each

        if (currentProgress < 100)
        {
            job.Progress = Math.Min(100, currentProgress + 12 + Random.Shared.Next(0, 5));
            stepIndex = Math.Min(ProcessingSteps.Length - 1, job.Progress / 12);
            job.CurrentStep = ProcessingSteps[stepIndex];
            job.Status = "processing";
        }

        if (job.Progress >= 100)
        {
            job.Status = "completed";
            job.Progress = 100;
            job.CurrentStep = "quality_validator";
            job.OutputUrl = $"/Home/Download/{job.Id}";
        }
    }

    [HttpGet]
    public IActionResult Download(string id)
    {
        var job = _jobStorage.GetJob(id);

        if (job == null)
        {
            return NotFound();
        }

        if (job.Simulated)
        {
            // Show demo download page
            ViewBag.JobId = id;
            ViewBag.Simulated = true;
            return View("Download");
        }

        if (!string.IsNullOrEmpty(job.OutputUrl) && !job.OutputUrl.StartsWith("/"))
        {
            return Redirect(job.OutputUrl);
        }

        ViewBag.JobId = id;
        ViewBag.Simulated = false;
        return View("Download");
    }

    [HttpGet]
    public async Task<IActionResult> Jobs()
    {
        var jobs = _jobStorage.GetAllJobs().Take(20).ToList();

        // Refresh status from API for non-simulated jobs
        foreach (var job in jobs.Where(j => !j.Simulated && j.Status != "completed" && j.Status != "error"))
        {
            try
            {
                var status = await _orchestratorService.GetStatusAsync(job.JobId);
                if (status != null)
                {
                    job.Status = status.Status;
                    job.Progress = status.Progress;
                    job.CurrentStep = status.CurrentStep;
                    job.OutputUrl = status.OutputUrl;
                    job.Error = status.Error;
                    _jobStorage.UpdateJob(job);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to refresh status for job {JobId}", job.JobId);
            }
        }

        return Json(jobs);
    }

    [HttpGet]
    public IActionResult Samples()
    {
        var samples = _sampleService.GetSamples();
        return Json(samples);
    }

    [HttpGet]
    public IActionResult Health()
    {
        return Json(new
        {
            status = "healthy",
            orchestratorAvailable = _orchestratorService.IsAvailable,
            orchestratorUrl = _configuration["Orchestrator:BaseUrl"]
        });
    }

    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    public IActionResult Error()
    {
        return View(new ErrorViewModel { RequestId = Activity.Current?.Id ?? HttpContext.TraceIdentifier });
    }
}
