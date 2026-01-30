using PptGenerator.Web.Models;

namespace PptGenerator.Web.Services;

public interface IJobStorageService
{
    void SaveJob(JobStatus job);
    JobStatus? GetJob(string jobId);
    IEnumerable<JobStatus> GetAllJobs();
    void UpdateJob(JobStatus job);
}
