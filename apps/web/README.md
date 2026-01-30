# PPT Generator - Web Test Interface (.NET MVC)

A simple ASP.NET Core MVC web interface for testing the PPT Generator service.

## Features

- Paste and submit JSON payloads
- Load sample payloads from the `/samples` folder
- JSON validation and formatting
- Async job submission with status polling
- Progress tracking and download link
- Job history

## Prerequisites

- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)

## Quick Start

```bash
# Navigate to web directory
cd web

# Restore dependencies
dotnet restore

# Run the application
dotnet run
```

Open https://localhost:5001 (or http://localhost:5000) in your browser.

## Configuration

Edit `appsettings.json` or use environment variables:

| Setting | Default | Description |
|---------|---------|-------------|
| `Orchestrator:BaseUrl` | `http://localhost:8080` | PPT Generator orchestrator URL |
| `Samples:Path` | `../samples` | Path to sample JSON files |

### Using Environment Variables

```bash
export Orchestrator__BaseUrl=http://localhost:8080
dotnet run
```

## Demo Mode

If the orchestrator is not running, the web app operates in "demo mode":
- Jobs are stored in-memory
- Status progresses through simulated steps
- Download link shows a placeholder page

This allows you to test the UI without running the full backend.

## Project Structure

```
web/
├── PptGenerator.Web.csproj    # Project file
├── Program.cs                  # Application entry point
├── appsettings.json           # Configuration
├── Controllers/
│   └── HomeController.cs      # Main controller
├── Models/
│   └── JobModels.cs           # Data models
├── Services/
│   ├── IOrchestratorService.cs
│   ├── OrchestratorService.cs
│   ├── IJobStorageService.cs
│   ├── InMemoryJobStorageService.cs
│   ├── ISampleService.cs
│   └── SampleService.cs
├── Views/
│   ├── _ViewImports.cshtml
│   ├── _ViewStart.cshtml
│   ├── Shared/
│   │   └── _Layout.cshtml
│   └── Home/
│       ├── Index.cshtml
│       ├── Download.cshtml
│       └── Error.cshtml
└── wwwroot/
    ├── css/
    │   └── site.css
    └── js/
        └── site.js
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Main page |
| `/Home/Submit` | POST | Submit a new job |
| `/Home/Status?id={jobId}` | GET | Get job status |
| `/Home/Download/{jobId}` | GET | Get download link |
| `/Home/Jobs` | GET | List all jobs |
| `/Home/Samples` | GET | List sample payloads |
| `/Home/Health` | GET | Health check |

## Development

### Running in Development Mode

```bash
dotnet watch run
```

### Building for Production

```bash
dotnet publish -c Release -o ./publish
```

### Docker

```dockerfile
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
WORKDIR /app
EXPOSE 80

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["PptGenerator.Web.csproj", "./"]
RUN dotnet restore
COPY . .
RUN dotnet build -c Release -o /app/build

FROM build AS publish
RUN dotnet publish -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "PptGenerator.Web.dll"]
```

## Screenshots

### Main Interface
- Large textarea for JSON input
- Sample loader dropdown
- Format/Validate/Clear buttons
- Submit button

### Status Tracking
- Progress bar with percentage
- Current processing step
- Status badge (queued/processing/completed/error)
- Download button when complete

### Job History
- List of recent jobs
- Click to view status
- Status badges
