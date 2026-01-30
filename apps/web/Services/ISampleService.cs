using PptGenerator.Web.Models;

namespace PptGenerator.Web.Services;

public interface ISampleService
{
    IEnumerable<SamplePayload> GetSamples();
}
