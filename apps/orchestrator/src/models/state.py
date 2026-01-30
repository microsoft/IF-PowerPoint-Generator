"""
State models for the LangGraph presentation generation pipeline.

The PipelineState is passed through all 8 nodes and accumulates
results at each stage.
"""
from typing import TypedDict, List, Dict, Any, Optional, Literal
from pydantic import BaseModel, Field
from enum import Enum
from datetime import datetime


class AudienceType(str, Enum):
    """Target audience types."""
    EXECUTIVE = "executive"
    TECHNICAL = "technical"
    BOARD = "board"
    OPERATIONAL = "operational"
    MIXED = "mixed"


class ToneType(str, Enum):
    """Presentation tone options."""
    FORMAL = "formal"
    CONVERSATIONAL = "conversational"
    URGENT = "urgent"
    INFORMATIVE = "informative"
    PERSUASIVE = "persuasive"


class DataType(str, Enum):
    """Classified data types."""
    BUDGET_ALLOCATION = "budget_allocation"
    TIME_SERIES = "time_series"
    COMPARISON = "comparison"
    HIERARCHICAL = "hierarchical"
    KPI_METRICS = "kpi_metrics"
    RISK_ASSESSMENT = "risk_assessment"
    PROJECT_STATUS = "project_status"
    GEOGRAPHIC = "geographic"
    TABULAR = "tabular"
    UNKNOWN = "unknown"
    FUNNEL = "funnel"
    FLOW = "flow"
    DISTRIBUTION = "distribution"
    SKILLS_GAP = "skills_gap"
    VENDOR_SCORING = "vendor_scoring"
    FREE_FORM_TEXT = "free_form_text"


class VisualizationType(str, Enum):
    """Visualization types for slides."""
    BAR_CHART = "bar_chart"
    STACKED_BAR = "stacked_bar"
    PIE_CHART = "pie_chart"
    DONUT_CHART = "donut_chart"
    LINE_CHART = "line_chart"
    AREA_CHART = "area_chart"
    TABLE = "table"
    KPI_CARDS = "kpi_cards"
    BULLET_POINTS = "bullet_points"
    TIMELINE = "timeline"
    HEATMAP = "heatmap"
    TREEMAP = "treemap"
    WATERFALL = "waterfall"
    GAUGE = "gauge"
    GROUPED_BAR = "grouped_bar"
    HORIZONTAL_BAR = "horizontal_bar"
    FUNNEL = "funnel"
    SANKEY = "sankey"
    RADAR = "radar"
    DIVERGING_BAR = "diverging_bar"
    TEXT_BLOCK = "text_block"


class ValidationStatus(str, Enum):
    """Validation result status."""
    PASSED = "passed"
    PASSED_WITH_WARNINGS = "passed_with_warnings"
    NEEDS_RETRY = "needs_retry"
    FAILED = "failed"


# --- Node 1: Context Interpreter Output ---
class AudienceProfile(BaseModel):
    """Profile of the target audience."""
    audience_type: AudienceType
    seniority_level: str = Field(description="e.g., C-level, Director, Manager")
    domain_expertise: str = Field(description="Expected domain knowledge level")
    key_concerns: List[str] = Field(description="What matters most to this audience")
    decision_making_power: bool = Field(description="Can this audience make decisions?")


class ContextAnalysis(BaseModel):
    """Output from the Context Interpreter node."""
    audience_profile: AudienceProfile
    presentation_goal: str = Field(description="Primary objective of the presentation")
    tone: ToneType
    time_constraint: Optional[str] = Field(default=None, description="e.g., '10 minutes', '30 slides max'")
    key_message: str = Field(description="The ONE thing the audience should remember")
    constraints: List[str] = Field(default_factory=list, description="Any constraints mentioned")


# --- Node 2: Data Classifier Output ---
class DataClassification(BaseModel):
    """Classification of a single data collection."""
    collection_id: str
    collection_title: str
    source_type: str
    data_type: DataType
    suggested_visualizations: List[VisualizationType]
    key_metrics: List[str] = Field(description="Important metrics identified in the data")
    data_quality_score: float = Field(ge=0, le=1, description="Quality score 0-1")
    insights_potential: str = Field(description="What story can this data tell?")
    classification_rationale: str = Field(default="", description="Explanation of WHY this data type was selected")
    pattern_confidence: Literal["high", "medium", "low"] = Field(default="medium", description="HIGH=exact pattern match, MEDIUM=partial, LOW=best-guess")
    primary_visualization: Optional[VisualizationType] = Field(default=None, description="The BEST chart type per prescriptive mapping")
    secondary_visualization: Optional[VisualizationType] = Field(default=None, description="Fallback chart type")
    detection_signals: List[str] = Field(default_factory=list, description="Which signals from mapping table were detected")


class ClassificationResult(BaseModel):
    """Output from the Data Classifier node."""
    classifications: List[DataClassification]
    overall_data_richness: str = Field(description="Overall assessment of data quality")
    recommended_focus_areas: List[str]


# --- Node 3: Narrative Architect Output ---
class SlideOutline(BaseModel):
    """Outline for a single slide."""
    slide_number: int
    slide_type: str = Field(description="e.g., title, executive_summary, data, conclusion")
    title_suggestion: str
    content_focus: str = Field(description="What this slide should communicate")
    data_source: Optional[str] = Field(default=None, description="Which data collection to use")
    visualization_hint: Optional[VisualizationType] = None
    speaker_note_hint: Optional[str] = None


class NarrativeStructure(BaseModel):
    """Output from the Narrative Architect node."""
    story_arc: str = Field(description="The narrative arc: e.g., 'Problem -> Analysis -> Solution -> Impact'")
    executive_summary: str = Field(description="2-3 sentence executive summary")
    slide_sequence: List[SlideOutline]
    key_transitions: List[str] = Field(description="How slides connect narratively")
    recommended_slide_count: int
    estimated_duration_minutes: int


# --- Node 4: Template Selector Output ---
class TemplateMatch(BaseModel):
    """Output from the Template Selector node."""
    selected_template_id: str
    template_name: str
    match_score: float = Field(ge=0, le=1)
    match_reasons: List[str]
    fallback_template_id: Optional[str] = None
    layout_recommendations: Dict[str, str] = Field(
        default_factory=dict,
        description="Recommended layout for each slide type"
    )


# --- Node 5: Visualization Strategist Output ---
class SeriesData(BaseModel):
    """A single data series for a chart."""
    name: str = Field(description="Series name (appears in legend)")
    values: List[float] = Field(description="Numeric values for this series")
    color: Optional[str] = Field(default=None, description="Hex color for this series (optional)")


class ChartDataConfig(BaseModel):
    """Explicit chart construction data from LLM - NO pattern detection needed."""
    categories: List[str] = Field(description="Category labels for X-axis")
    series: List[SeriesData] = Field(description="Data series with values")

    # Formatting
    value_format: str = Field(default="#,##0", description="Number format for values")
    show_data_labels: bool = Field(default=True)
    show_legend: bool = Field(default=True)
    legend_position: str = Field(default="bottom", description="bottom, right, top, left")

    # Axis labels
    x_axis_label: Optional[str] = None
    y_axis_label: Optional[str] = None


class ChartConfig(BaseModel):
    """Configuration for a single chart."""
    chart_id: str
    chart_type: VisualizationType
    data_source: str = Field(description="Key path in data collection")
    title: str
    x_axis_label: Optional[str] = None
    y_axis_label: Optional[str] = None
    color_scheme: Optional[str] = Field(default="brand", description="brand, sequential, diverging")
    annotations: List[str] = Field(default_factory=list)
    highlight_values: List[str] = Field(default_factory=list, description="Values to emphasize")
    chart_data: Optional[ChartDataConfig] = Field(default=None, description="Explicit chart data from LLM - if provided, skip pattern detection")


class SlideVisualization(BaseModel):
    """Visualization plan for a single slide."""
    slide_number: int
    layout_type: str = Field(description="e.g., full_chart, split, comparison")
    primary_visual: Optional[ChartConfig] = None
    secondary_visual: Optional[ChartConfig] = None
    text_placement: str = Field(description="Where text should go relative to visuals")
    fallback_visual: Optional[ChartConfig] = Field(default=None, description="Guaranteed fallback if primary/secondary fail")
    visualization_rationale: str = Field(default="", description="Why this chart configuration was chosen")
    guaranteed_output: bool = Field(default=True, description="If True, this slide MUST produce a visualization")


class VisualizationPlan(BaseModel):
    """Output from the Visualization Strategist node."""
    slide_visualizations: List[SlideVisualization]
    color_palette: List[str] = Field(description="Hex colors to use")
    chart_style: str = Field(description="Overall chart styling approach")


# --- Node 6: Content Generator Output ---
class SlideContent(BaseModel):
    """Generated content for a single slide."""
    slide_number: int
    title: str
    subtitle: Optional[str] = None
    bullet_points: List[str] = Field(default_factory=list)
    key_insight: Optional[str] = Field(default=None, description="Callout insight")
    speaker_notes: Optional[str] = None
    data_labels: Dict[str, str] = Field(default_factory=dict, description="Labels for chart data points")


class GeneratedContent(BaseModel):
    """Output from the Content Generator node."""
    slides: List[SlideContent]
    document_title: str
    document_subtitle: Optional[str] = None


# --- Node 7: Slide Builder Output ---
class BuildResult(BaseModel):
    """Output from the Slide Builder node."""
    output_blob_path: str
    slide_count: int
    file_size_bytes: int
    chart_images_generated: List[str]
    build_duration_ms: int
    warnings: List[str] = Field(default_factory=list)


# --- Node 8: Quality Validator Output ---
class ValidationResult(BaseModel):
    """Output from the Quality Validator node."""
    status: ValidationStatus
    quality_score: float = Field(ge=0, le=1, description="Overall quality score 0-1")
    issues_found: List[str] = Field(default_factory=list)
    retry_recommended: Optional[str] = Field(default=None, description="retry_viz, retry_content, or None")
    validation_details: Dict[str, Any] = Field(default_factory=dict)


# --- Pipeline State (passed through all nodes) ---
class PipelineState(TypedDict, total=False):
    """
    State object passed through all LangGraph nodes.
    Each node adds its output to this state.
    """
    # Input data
    job_id: str
    request_id: str
    presentation_context: Dict[str, Any]
    data_collections: List[Dict[str, Any]]
    brand_config: Dict[str, Any]
    callback_url: Optional[str]

    # Node outputs
    context_analysis: Optional[ContextAnalysis]
    classification_result: Optional[ClassificationResult]
    narrative_structure: Optional[NarrativeStructure]
    template_match: Optional[TemplateMatch]
    visualization_plan: Optional[VisualizationPlan]
    generated_content: Optional[GeneratedContent]
    build_result: Optional[BuildResult]
    validation_result: Optional[ValidationResult]

    # Processing metadata
    current_node: str
    progress: int
    started_at: str
    errors: List[Dict[str, Any]]
    retry_count: int

    # Final output
    download_url: Optional[str]
    status: str
