"""
Pydantic models for API request/response validation.
"""
from typing import Optional, List, Any, Dict, Union
from pydantic import BaseModel, Field
from datetime import datetime
from enum import Enum
from uuid import UUID
import uuid


class JobStatus(str, Enum):
    QUEUED = "queued"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    COMPLETED_WITH_WARNINGS = "completed_with_warnings"


class ProcessingStage(str, Enum):
    CONTEXT = "context"
    CLASSIFY = "classify"
    NARRATIVE = "narrative"
    TEMPLATE = "template"
    VISUALIZE = "visualize"
    CONTENT = "content"
    BUILD = "build"
    VALIDATE = "validate"
    # Additional stages used during processing
    INITIALIZING = "initializing"
    SELECTING_TEMPLATE = "selecting_template"
    ANALYZING_DATA = "analyzing_data"
    CREATING_SLIDES = "creating_slides"
    GENERATING_CONTENT = "generating_content"
    APPLYING_BRANDING = "applying_branding"
    FINALIZING = "finalizing"
    COMPLETED = "completed"
    FAILED = "failed"


# Request Models
class BrandConfig(BaseModel):
    """Optional brand configuration for presentation styling."""
    primaryColor: str = Field(default="#003366", pattern=r"^#[0-9A-Fa-f]{6}$")
    secondaryColor: str = Field(default="#E8F0F8", pattern=r"^#[0-9A-Fa-f]{6}$")
    baseColor: str = Field(default="#FFFFFF", pattern=r"^#[0-9A-Fa-f]{6}$")


class RequestorMetadata(BaseModel):
    """Metadata about the requesting application and user."""
    appId: UUID = Field(default_factory=uuid.uuid4, description="Application identifier UUID")
    userId: Optional[UUID] = Field(None, description="User identifier")
    tenantId: Optional[UUID] = Field(None, description="Tenant identifier")
    sessionId: Optional[UUID] = Field(None, description="Session identifier")
    correlationId: Optional[UUID] = Field(None, description="Correlation ID for tracing")


class PresentationContext(BaseModel):
    """Context for the presentation generation."""
    title: Optional[str] = Field(default=None, max_length=200, description="Will be inferred from data if not provided")
    subtitle: Optional[str] = Field(None, max_length=200)
    author: Optional[str] = Field(None, max_length=100)
    date: Optional[str] = Field(None, max_length=50)
    context: Optional[str] = Field(default=None, description="Will be inferred from data if not provided")
    templatePreference: Optional[str] = Field(None, description="Optional template hint")


class DataCollection(BaseModel):
    """A single data collection for the presentation."""
    collection_id: UUID = Field(default_factory=uuid.uuid4, description="Unique identifier for this collection")
    title: Optional[str] = Field(default=None, max_length=200, description="Will be inferred from data if not provided")
    source_type: Optional[str] = Field(None, description="Source type: internal_chat, manual, api, etc.")
    data: Any = Field(..., description="Raw data in any structure")


class GenerationRequest(BaseModel):
    """Complete request for presentation generation."""
    request_id: UUID = Field(default_factory=uuid.uuid4, alias="requestId")
    callbackUrl: str = Field(..., description="Webhook URL for completion notification")
    requestorMetadata: Optional[RequestorMetadata] = None
    brandConfig: Optional[BrandConfig] = None
    presentationContext: Optional[PresentationContext] = Field(default=None, description="Will be inferred from data if not provided")
    data_collection: List[DataCollection] = Field(..., min_length=1, max_length=50, alias="dataCollections")

    class Config:
        populate_by_name = True


# Response Models
class GenerationAcceptedResponse(BaseModel):
    """Response when a generation request is accepted."""
    jobId: UUID
    status: JobStatus = JobStatus.QUEUED
    statusUrl: str
    estimatedCompletionSeconds: int = 60


class JobStatusResponse(BaseModel):
    """Response for job status queries."""
    jobId: UUID
    status: JobStatus
    stage: Optional[ProcessingStage] = None
    progress: int = Field(ge=0, le=100)
    startedAt: Optional[datetime] = None
    completedAt: Optional[datetime] = None
    downloadUrl: Optional[str] = None
    expiresAt: Optional[datetime] = None
    metadata: Optional[Dict[str, Any]] = None
    warnings: List[Dict[str, Any]] = Field(default_factory=list)
    error: Optional[Dict[str, Any]] = None


class WebhookPayload(BaseModel):
    """Payload sent to callback URL on completion."""
    event: str  # presentation.completed or presentation.failed
    jobId: UUID
    requestId: UUID
    status: JobStatus
    downloadUrl: Optional[str] = None
    expiresAt: Optional[datetime] = None
    metadata: Optional[Dict[str, Any]] = None
    warnings: List[Dict[str, Any]] = Field(default_factory=list)
    error: Optional[Dict[str, Any]] = None


# Internal Models
class JobMessage(BaseModel):
    """Message sent to Service Bus for processing."""
    jobId: UUID
    requestId: UUID
    requestorMetadata: Optional[RequestorMetadata]
    brandConfig: Optional[BrandConfig] = Field(default_factory=BrandConfig)
    presentationContext: Optional[PresentationContext] = Field(default=None)
    data_collection: List[DataCollection] = Field(alias="dataCollections")
    callbackUrl: str
    receivedAt: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        populate_by_name = True
