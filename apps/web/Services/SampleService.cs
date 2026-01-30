using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using PptGenerator.Web.Models;

namespace PptGenerator.Web.Services;

public class SampleService : ISampleService
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<SampleService> _logger;
    private readonly string _samplesPath;

    public SampleService(IConfiguration configuration, ILogger<SampleService> logger)
    {
        _configuration = configuration;
        _logger = logger;

        // Try multiple locations for samples
        var possiblePaths = new[]
        {
            _configuration["Samples:Path"] ?? "../samples",
            "../samples",
            "../../samples",
            "../../../samples",
            "samples",
            Path.Combine(AppContext.BaseDirectory, "../samples"),
            Path.Combine(AppContext.BaseDirectory, "../../samples"),
            Path.Combine(AppContext.BaseDirectory, "samples"),
            Path.Combine(Directory.GetCurrentDirectory(), "../samples"),
            Path.Combine(Directory.GetCurrentDirectory(), "samples")
        };

        _samplesPath = possiblePaths
            .Select(p => Path.GetFullPath(p))
            .FirstOrDefault(Directory.Exists) ?? Path.GetFullPath("samples");

        _logger.LogInformation("Samples path resolved to: {Path} (exists: {Exists})", _samplesPath, Directory.Exists(_samplesPath));
    }

    public IEnumerable<SamplePayload> GetSamples()
    {
        var samples = new List<SamplePayload>();

        if (!Directory.Exists(_samplesPath))
        {
            _logger.LogWarning("Samples directory not found: {Path}", _samplesPath);
            return samples;
        }

        var files = Directory.GetFiles(_samplesPath, "*.json").OrderBy(f => f);

        foreach (var file in files)
        {
            try
            {
                var content = File.ReadAllText(file);
                var json = JObject.Parse(content);

                var dataCollection = json["data_collection"] as JArray;
                var firstItem = dataCollection?.FirstOrDefault() as JObject;

                samples.Add(new SamplePayload
                {
                    Filename = Path.GetFileName(file),
                    Title = firstItem?["title"]?.ToString() ?? Path.GetFileNameWithoutExtension(file),
                    SourceType = firstItem?["source_type"]?.ToString() ?? "unknown",
                    Content = JsonConvert.SerializeObject(json, Formatting.Indented)
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error reading sample file: {File}", file);
            }
        }

        return samples;
    }
}
