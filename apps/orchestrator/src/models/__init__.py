"""
Models for the orchestrator.

V3 Architecture (Assistants API):
- v3.py: Contains all models for the Assistants API approach
- state.py: Legacy models (kept for reference/backward compatibility)
"""

# V3 Models (Primary)
from .v3 import (
    SlideType,
    Slide,
    PresentationMetadata,
    PresentationResponse,
    BrandConfig,
    DataCollection,
    GenerateRequest,
    GenerateResponse,
    JobStatus,
)

# Legacy State Models (for reference/backward compatibility)
from .state import (
    PipelineState,
    AudienceType,
    ToneType,
    DataType,
    VisualizationType,
    ValidationStatus,
    AudienceProfile,
    ContextAnalysis,
    DataClassification,
    ClassificationResult,
    SlideOutline,
    NarrativeStructure,
    TemplateMatch,
    SeriesData,
    ChartDataConfig,
    ChartConfig,
    SlideVisualization,
    VisualizationPlan,
    SlideContent,
    GeneratedContent,
    BuildResult,
    ValidationResult,
)

# Export V3 models as primary
__all__ = [
    # V3 Models (Primary)
    "SlideType",
    "Slide",
    "PresentationMetadata",
    "PresentationResponse",
    "BrandConfig",
    "DataCollection",
    "GenerateRequest",
    "GenerateResponse",
    "JobStatus",
    # Legacy Models (for backward compatibility)
    "PipelineState",
    "AudienceType",
    "ToneType",
    "DataType",
    "VisualizationType",
    "ValidationStatus",
    "AudienceProfile",
    "ContextAnalysis",
    "DataClassification",
    "ClassificationResult",
    "SlideOutline",
    "NarrativeStructure",
    "TemplateMatch",
    "SeriesData",
    "ChartDataConfig",
    "ChartConfig",
    "SlideVisualization",
    "VisualizationPlan",
    "SlideContent",
    "GeneratedContent",
    "BuildResult",
    "ValidationResult",
]
