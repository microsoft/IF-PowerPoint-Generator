-- ============================================
-- PPT Generator Service - SQL Schema
-- Database: ppt-telemetry
-- Version: 1.0.0
-- ============================================

-- Drop existing tables if they exist (for clean deployment)
IF OBJECT_ID('dbo.ErrorLog', 'U') IS NOT NULL DROP TABLE dbo.ErrorLog;
IF OBJECT_ID('dbo.TemplateUsage', 'U') IS NOT NULL DROP TABLE dbo.TemplateUsage;
IF OBJECT_ID('dbo.DataCollectionStats', 'U') IS NOT NULL DROP TABLE dbo.DataCollectionStats;
IF OBJECT_ID('dbo.ProcessingMetrics', 'U') IS NOT NULL DROP TABLE dbo.ProcessingMetrics;
IF OBJECT_ID('dbo.JobRequests', 'U') IS NOT NULL DROP TABLE dbo.JobRequests;

GO

-- ============================================
-- Table: JobRequests
-- Core request tracking for all generation jobs
-- ============================================
CREATE TABLE dbo.JobRequests (
    JobId UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    RequestId UNIQUEIDENTIFIER NOT NULL,

    -- Requestor metadata
    RequestorAppId UNIQUEIDENTIFIER NULL,
    RequestorUserId UNIQUEIDENTIFIER NULL,
    RequestorTenantId UNIQUEIDENTIFIER NULL,

    -- Request metadata
    TemplatePreference NVARCHAR(100) NULL,
    TemplateUsed NVARCHAR(100) NULL,
    DataCollectionCount INT NULL,
    ContextLength INT NULL,

    -- Timing
    ReceivedAt DATETIME2 DEFAULT GETUTCDATE(),
    ProcessingStartedAt DATETIME2 NULL,
    CompletedAt DATETIME2 NULL,
    DurationMs INT NULL,

    -- Status
    Status NVARCHAR(30) DEFAULT 'queued',
    ErrorCode NVARCHAR(50) NULL,
    ErrorMessage NVARCHAR(500) NULL,
    WarningCount INT DEFAULT 0,

    -- Output
    OutputBlobUrl NVARCHAR(500) NULL,
    SlideCount INT NULL,

    -- Audit
    CreatedAt DATETIME2 DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- Indexes for common queries
CREATE INDEX IX_JobRequests_RequestId ON dbo.JobRequests(RequestId);
CREATE INDEX IX_JobRequests_RequestorAppId ON dbo.JobRequests(RequestorAppId);
CREATE INDEX IX_JobRequests_Status ON dbo.JobRequests(Status);
CREATE INDEX IX_JobRequests_ReceivedAt ON dbo.JobRequests(ReceivedAt);
CREATE INDEX IX_JobRequests_TemplateUsed ON dbo.JobRequests(TemplateUsed);
CREATE INDEX IX_JobRequests_RequestorTenantId ON dbo.JobRequests(RequestorTenantId);

GO

-- ============================================
-- Table: ProcessingMetrics
-- Per-node processing metrics for performance analysis
-- ============================================
CREATE TABLE dbo.ProcessingMetrics (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    JobId UNIQUEIDENTIFIER NOT NULL,
    NodeName NVARCHAR(50) NOT NULL,
    StartedAt DATETIME2 NULL,
    CompletedAt DATETIME2 NULL,
    DurationMs INT NULL,
    TokensUsed INT DEFAULT 0,
    Success BIT DEFAULT 1,
    ErrorMessage NVARCHAR(500) NULL,

    CONSTRAINT FK_ProcessingMetrics_JobRequests
        FOREIGN KEY (JobId) REFERENCES dbo.JobRequests(JobId)
        ON DELETE CASCADE
);

CREATE INDEX IX_ProcessingMetrics_JobId ON dbo.ProcessingMetrics(JobId);
CREATE INDEX IX_ProcessingMetrics_NodeName ON dbo.ProcessingMetrics(NodeName);

GO

-- ============================================
-- Table: DataCollectionStats
-- Analytics on data types and visualizations used
-- ============================================
CREATE TABLE dbo.DataCollectionStats (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    JobId UNIQUEIDENTIFIER NOT NULL,
    CollectionId UNIQUEIDENTIFIER NOT NULL,
    CollectionTitle NVARCHAR(200) NULL,
    SourceType NVARCHAR(50) NULL,
    InferredDataType NVARCHAR(50) NULL,
    VisualizationType NVARCHAR(50) NULL,
    WasFallback BIT DEFAULT 0,

    CONSTRAINT FK_DataCollectionStats_JobRequests
        FOREIGN KEY (JobId) REFERENCES dbo.JobRequests(JobId)
        ON DELETE CASCADE
);

CREATE INDEX IX_DataCollectionStats_JobId ON dbo.DataCollectionStats(JobId);
CREATE INDEX IX_DataCollectionStats_CollectionId ON dbo.DataCollectionStats(CollectionId);
CREATE INDEX IX_DataCollectionStats_InferredDataType ON dbo.DataCollectionStats(InferredDataType);
CREATE INDEX IX_DataCollectionStats_VisualizationType ON dbo.DataCollectionStats(VisualizationType);

GO

-- ============================================
-- Table: TemplateUsage
-- Template selection analytics
-- ============================================
CREATE TABLE dbo.TemplateUsage (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    JobId UNIQUEIDENTIFIER NOT NULL,
    TemplateId NVARCHAR(100) NOT NULL,
    TemplateVersion NVARCHAR(20) NULL,
    WasExplicitPreference BIT DEFAULT 0,
    WasAISelected BIT DEFAULT 0,
    WasFallback BIT DEFAULT 0,

    CONSTRAINT FK_TemplateUsage_JobRequests
        FOREIGN KEY (JobId) REFERENCES dbo.JobRequests(JobId)
        ON DELETE CASCADE
);

CREATE INDEX IX_TemplateUsage_TemplateId ON dbo.TemplateUsage(TemplateId);

GO

-- ============================================
-- Table: ErrorLog
-- Detailed error logging for debugging
-- ============================================
CREATE TABLE dbo.ErrorLog (
    Id BIGINT IDENTITY(1,1) PRIMARY KEY,
    JobId UNIQUEIDENTIFIER NULL,
    OccurredAt DATETIME2 DEFAULT GETUTCDATE(),
    ErrorCode NVARCHAR(50) NULL,
    ErrorMessage NVARCHAR(MAX) NULL,
    StackTrace NVARCHAR(MAX) NULL,
    NodeName NVARCHAR(50) NULL,
    AdditionalData NVARCHAR(MAX) NULL
);

CREATE INDEX IX_ErrorLog_JobId ON dbo.ErrorLog(JobId);
CREATE INDEX IX_ErrorLog_ErrorCode ON dbo.ErrorLog(ErrorCode);
CREATE INDEX IX_ErrorLog_OccurredAt ON dbo.ErrorLog(OccurredAt);

GO

PRINT 'Tables created successfully';
GO
