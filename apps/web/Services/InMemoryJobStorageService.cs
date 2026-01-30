using System.Collections.Concurrent;
using PptGenerator.Web.Models;

namespace PptGenerator.Web.Services;

public class InMemoryJobStorageService : IJobStorageService
{
    private readonly ConcurrentDictionary<string, JobStatus> _jobs = new();

    public void SaveJob(JobStatus job)
    {
        _jobs[job.Id] = job;
    }

    public JobStatus? GetJob(string jobId)
    {
        return _jobs.TryGetValue(jobId, out var job) ? job : null;
    }

    public IEnumerable<JobStatus> GetAllJobs()
    {
        return _jobs.Values.OrderByDescending(j => j.CreatedAt);
    }

    public void UpdateJob(JobStatus job)
    {
        _jobs[job.Id] = job;
    }
}
