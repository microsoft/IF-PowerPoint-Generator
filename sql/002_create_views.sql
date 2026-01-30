-- ============================================
-- PPT Generator Service - Reporting Views
-- For Power App dashboards and analytics
-- ============================================

-- Drop existing views
IF OBJECT_ID('dbo.vw_DailyJobSummary', 'V') IS NOT NULL DROP VIEW dbo.vw_DailyJobSummary;
IF OBJECT_ID('dbo.vw_TemplatePopularity', 'V') IS NOT NULL DROP VIEW dbo.vw_TemplatePopularity;
IF OBJECT_ID('dbo.vw_VisualizationPatterns', 'V') IS NOT NULL DROP VIEW dbo.vw_VisualizationPatterns;
IF OBJECT_ID('dbo.vw_NodePerformance', 'V') IS NOT NULL DROP VIEW dbo.vw_NodePerformance;
IF OBJECT_ID('dbo.vw_AppUsage', 'V') IS NOT NULL DROP VIEW dbo.vw_AppUsage;
IF OBJECT_ID('dbo.vw_RecentErrors', 'V') IS NOT NULL DROP VIEW dbo.vw_RecentErrors;
IF OBJECT_ID('dbo.vw_JobDetails', 'V') IS NOT NULL DROP VIEW dbo.vw_JobDetails;

GO

-- ============================================
-- View: vw_DailyJobSummary
-- Daily aggregated job metrics
-- ============================================
CREATE VIEW dbo.vw_DailyJobSummary AS
SELECT
    CAST(ReceivedAt AS DATE) AS JobDate,
    RequestorAppId,
    COUNT(*) AS TotalJobs,
    SUM(CASE WHEN Status = 'completed' THEN 1 ELSE 0 END) AS SuccessfulJobs,
    SUM(CASE WHEN Status = 'completed_with_warnings' THEN 1 ELSE 0 END) AS JobsWithWarnings,
    SUM(CASE WHEN Status = 'failed' THEN 1 ELSE 0 END) AS FailedJobs,
    AVG(DurationMs) AS AvgDurationMs,
    AVG(SlideCount) AS AvgSlideCount,
    AVG(DataCollectionCount) AS AvgDataCollections,
    SUM(SlideCount) AS TotalSlidesGenerated,
    CAST(SUM(CASE WHEN Status IN ('completed', 'completed_with_warnings') THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) AS DECIMAL(5,2)) AS SuccessRate
FROM dbo.JobRequests
GROUP BY CAST(ReceivedAt AS DATE), RequestorAppId;

GO

-- ============================================
-- View: vw_TemplatePopularity
-- Template usage statistics
-- ============================================
CREATE VIEW dbo.vw_TemplatePopularity AS
SELECT
    TemplateUsed,
    COUNT(*) AS UsageCount,
    AVG(SlideCount) AS AvgSlides,
    AVG(DurationMs) AS AvgDurationMs,
    SUM(CASE WHEN Status IN ('completed', 'completed_with_warnings') THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) AS SuccessRate,
    MIN(ReceivedAt) AS FirstUsed,
    MAX(ReceivedAt) AS LastUsed
FROM dbo.JobRequests
WHERE TemplateUsed IS NOT NULL
GROUP BY TemplateUsed;

GO

-- ============================================
-- View: vw_VisualizationPatterns
-- Data type to visualization mapping analysis
-- ============================================
CREATE VIEW dbo.vw_VisualizationPatterns AS
SELECT
    InferredDataType,
    VisualizationType,
    COUNT(*) AS UsageCount,
    SUM(CASE WHEN WasFallback = 1 THEN 1 ELSE 0 END) AS FallbackCount,
    CAST(SUM(CASE WHEN WasFallback = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) AS DECIMAL(5,2)) AS FallbackRate
FROM dbo.DataCollectionStats
GROUP BY InferredDataType, VisualizationType;

GO

-- ============================================
-- View: vw_NodePerformance
-- Processing node performance metrics
-- ============================================
CREATE VIEW dbo.vw_NodePerformance AS
WITH Percentiles AS (
    SELECT DISTINCT
        NodeName,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DurationMs) OVER (PARTITION BY NodeName) AS MedianDurationMs,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY DurationMs) OVER (PARTITION BY NodeName) AS P95DurationMs
    FROM dbo.ProcessingMetrics
),
Aggregates AS (
    SELECT
        NodeName,
        COUNT(*) AS ExecutionCount,
        AVG(DurationMs) AS AvgDurationMs,
        MIN(DurationMs) AS MinDurationMs,
        MAX(DurationMs) AS MaxDurationMs,
        AVG(TokensUsed) AS AvgTokensUsed,
        SUM(TokensUsed) AS TotalTokensUsed,
        SUM(CASE WHEN Success = 1 THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(*), 0) AS SuccessRate
    FROM dbo.ProcessingMetrics
    GROUP BY NodeName
)
SELECT
    a.NodeName,
    a.ExecutionCount,
    a.AvgDurationMs,
    a.MinDurationMs,
    a.MaxDurationMs,
    p.MedianDurationMs,
    p.P95DurationMs,
    a.AvgTokensUsed,
    a.TotalTokensUsed,
    a.SuccessRate
FROM Aggregates a
JOIN Percentiles p ON a.NodeName = p.NodeName;

GO

-- ============================================
-- View: vw_AppUsage
-- Usage statistics by requesting application
-- ============================================
CREATE VIEW dbo.vw_AppUsage AS
SELECT
    RequestorAppId,
    RequestorTenantId,
    COUNT(*) AS TotalRequests,
    COUNT(DISTINCT RequestorUserId) AS UniqueUsers,
    SUM(CASE WHEN Status IN ('completed', 'completed_with_warnings') THEN 1 ELSE 0 END) AS SuccessfulJobs,
    AVG(DataCollectionCount) AS AvgDataCollections,
    AVG(SlideCount) AS AvgSlidesPerJob,
    SUM(SlideCount) AS TotalSlidesGenerated,
    MIN(ReceivedAt) AS FirstRequest,
    MAX(ReceivedAt) AS LastRequest
FROM dbo.JobRequests
GROUP BY RequestorAppId, RequestorTenantId;

GO

-- ============================================
-- View: vw_RecentErrors
-- Recent errors for monitoring
-- ============================================
CREATE VIEW dbo.vw_RecentErrors AS
SELECT TOP 100
    e.Id,
    e.JobId,
    j.RequestorAppId,
    e.OccurredAt,
    e.ErrorCode,
    e.ErrorMessage,
    e.NodeName,
    j.ContextLength,
    j.DataCollectionCount
FROM dbo.ErrorLog e
LEFT JOIN dbo.JobRequests j ON e.JobId = j.JobId
ORDER BY e.OccurredAt DESC;

GO

-- ============================================
-- View: vw_JobDetails
-- Comprehensive job details for investigation
-- ============================================
CREATE VIEW dbo.vw_JobDetails AS
SELECT
    j.JobId,
    j.RequestId,
    j.RequestorAppId,
    j.RequestorUserId,
    j.RequestorTenantId,
    j.TemplatePreference,
    j.TemplateUsed,
    j.DataCollectionCount,
    j.SlideCount,
    j.Status,
    j.DurationMs,
    j.ReceivedAt,
    j.ProcessingStartedAt,
    j.CompletedAt,
    j.ErrorCode,
    j.ErrorMessage,
    j.WarningCount,
    j.OutputBlobUrl,
    (
        SELECT STRING_AGG(NodeName + ':' + CAST(DurationMs AS VARCHAR), ', ')
        FROM dbo.ProcessingMetrics pm
        WHERE pm.JobId = j.JobId
    ) AS NodeTimings,
    (
        SELECT COUNT(*)
        FROM dbo.DataCollectionStats dcs
        WHERE dcs.JobId = j.JobId AND dcs.WasFallback = 1
    ) AS FallbackVisualizationCount
FROM dbo.JobRequests j;

GO

PRINT 'Views created successfully';
GO
