using PptGenerator.Web.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container
builder.Services.AddControllersWithViews()
    .AddNewtonsoftJson(options =>
    {
        options.SerializerSettings.Formatting = Newtonsoft.Json.Formatting.Indented;
    });

// Register services
builder.Services.AddHttpClient<IOrchestratorService, OrchestratorService>(client =>
{
    var baseUrl = builder.Configuration["Orchestrator:BaseUrl"] ?? "http://localhost:8080";
    // Ensure trailing slash for correct relative URL resolution
    if (!baseUrl.EndsWith("/"))
        baseUrl += "/";
    client.BaseAddress = new Uri(baseUrl);
    client.Timeout = TimeSpan.FromSeconds(30);
});

builder.Services.AddSingleton<IJobStorageService, InMemoryJobStorageService>();
builder.Services.AddSingleton<ISampleService, SampleService>();

var app = builder.Build();

// Configure the HTTP request pipeline
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();
