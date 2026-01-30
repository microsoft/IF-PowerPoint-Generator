"""
V3 Models for Assistants API Architecture

These models define the simplified schema for the single-call Assistants API approach.
The LLM generates everything; the orchestrator just assembles.
"""
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any, Union, Literal
from enum import Enum


# --- Chart Blueprint Models (for local rendering) ---

class ChartType(str, Enum):
    """Supported chart types for blueprint rendering."""
    HORIZONTAL_BAR = "horizontal_bar"
    GROUPED_BAR = "grouped_bar"
    STACKED_BAR = "stacked_bar"
    DONUT = "donut"
    LINE = "line"
    AREA = "area"
    WATERFALL = "waterfall"
    DIVERGING_BAR = "diverging_bar"


class ValueFormat(str, Enum):
    """How to format numeric values in charts."""
    NUMBER = "number"
    PERCENT = "percent"
    CURRENCY = "currency"
    CURRENCY_K = "currency_k"
    CURRENCY_M = "currency_m"


class LegendPosition(str, Enum):
    """Legend placement options."""
    BOTTOM = "bottom"
    RIGHT = "right"
    TOP = "top"
    NONE = "none"


class SeriesData(BaseModel):
    """A data series for charts."""
    name: str = Field(..., description="Series name (for legend)")
    values: List[Union[float, int]] = Field(..., description="Numeric values")
    color: Optional[str] = Field(None, description="Hex color override (e.g., '#003366')")


class ChartBlueprint(BaseModel):
    """
    Blueprint for a chart to be rendered locally by the orchestrator.

    Instead of generating images in Code Interpreter, the Assistant returns
    these blueprints which are rendered using Plotly + kaleido locally.
    """
    chart_id: str = Field(..., description="Unique ID matching chart_file reference (e.g., 'chart_1')")
    chart_type: ChartType = Field(..., description="Type of chart to render")

    # Data
    categories: List[str] = Field(..., description="Category labels (X or Y axis)")
    series: List[SeriesData] = Field(..., description="One or more data series")

    # For waterfall charts
    measures: Optional[List[Literal["absolute", "relative", "total"]]] = Field(
        None, description="Waterfall measure types (one per category)"
    )

    # Titles and labels
    title: str = Field(..., description="Chart title (insight-driven, includes key number)")
    subtitle: Optional[str] = Field(None, description="Optional subtitle")
    x_axis_label: Optional[str] = Field(None, description="X-axis label")
    y_axis_label: Optional[str] = Field(None, description="Y-axis label")

    # Formatting
    value_format: ValueFormat = Field(
        default=ValueFormat.NUMBER,
        description="How to format data labels"
    )
    show_data_labels: bool = Field(default=True, description="Show values on chart")
    show_legend: bool = Field(default=True, description="Show legend")
    legend_position: LegendPosition = Field(
        default=LegendPosition.BOTTOM,
        description="Legend placement"
    )

    # Donut-specific
    center_text: Optional[str] = Field(None, description="Text for donut center (e.g., 'Total')")
    center_value: Optional[str] = Field(None, description="Value for donut center (e.g., '$6.9M')")

    # Styling overrides
    colors: Optional[List[str]] = Field(None, description="Custom color palette (hex codes)")
    highlight_index: Optional[int] = Field(None, description="Index to visually highlight")
    sort_descending: bool = Field(default=True, description="Sort bars by value (for bar charts)")

    class Config:
        use_enum_values = True


class SlideType(str, Enum):
    """Types of slides in the presentation."""
    TITLE = "title"
    EXECUTIVE_SUMMARY = "executive_summary"
    DATA = "data"
    SECTION_HEADER = "section_header"
    CONCLUSION = "conclusion"
    TEXT = "text"


class Slide(BaseModel):
    """
    A single slide definition returned by the Assistant.

    The orchestrator uses this to assemble the PowerPoint.
    """
    slide_number: int = Field(..., ge=1, description="Slide position in deck")
    slide_type: SlideType = Field(..., description="Type of slide layout to use")
    title: str = Field(..., description="Slide title (insight-driven, 5-10 words)")
    subtitle: Optional[str] = Field(None, description="Optional subtitle for title/section slides")
    chart_file: Optional[str] = Field(None, description="Filename of generated chart PNG, or null")
    chart_blueprint: Optional[ChartBlueprint] = Field(
        None, description="Blueprint for local chart rendering (replaces Code Interpreter)"
    )
    bullets: List[str] = Field(default_factory=list, description="Data-rich bullet points")
    key_insight: Optional[str] = Field(None, description="Single most important takeaway")
    speaker_notes: Optional[str] = Field(None, description="Detailed presenter notes")
    data_source: Optional[str] = Field(None, description="Reference to data collection visualized")


class PresentationMetadata(BaseModel):
    """Metadata about the generated presentation."""
    total_slides: int = Field(..., description="Total number of slides")
    charts_generated: int = Field(..., description="Number of chart images generated")
    narrative_arc: Optional[str] = Field(None, description="Description of story flow")
    data_sources_used: List[str] = Field(default_factory=list, description="Data collections analyzed")


class PresentationResponse(BaseModel):
    """
    Complete response from the Assistant.

    Contains everything needed to assemble the PowerPoint:
    - Slide definitions (titles, bullets, speaker notes)
    - Chart file references (PNG filenames generated by Code Interpreter)
    - Metadata about the presentation
    """
    presentation_title: str = Field(..., description="Main presentation title")
    presentation_subtitle: Optional[str] = Field(None, description="Optional subtitle/date")
    slides: List[Slide] = Field(..., description="Ordered list of slide definitions")
    metadata: PresentationMetadata = Field(..., description="Presentation metadata")


# --- Request Models ---

class BrandConfig(BaseModel):
    """Brand configuration for styling."""
    primary_color: str = Field(default="#003366", alias="primaryColor")
    secondary_color: str = Field(default="#50E6FF", alias="secondaryColor")
    accent_color: Optional[str] = Field(None, alias="accentColor")
    logo_url: Optional[str] = Field(None, alias="logoUrl")

    class Config:
        populate_by_name = True


class DataCollection(BaseModel):
    """A collection of data to visualize."""
    title: Optional[str] = Field(None, description="Optional title for this data")
    source_type: Optional[str] = Field(None, description="Source type (json, csv, etc)")
    data: Dict[str, Any] = Field(..., description="The actual data")


class GenerateRequest(BaseModel):
    """Request to generate a presentation."""
    title: Optional[str] = Field(default=None, description="Presentation title - will be inferred from data if not provided")
    audience: Optional[str] = Field("executives", description="Target audience")
    data_collections: List[DataCollection] = Field(..., description="Data to visualize")
    brand_config: Optional[BrandConfig] = Field(None, description="Brand styling")
    template_id: Optional[str] = Field(None, description="Template to use")


class GenerateResponse(BaseModel):
    """Response from generate endpoint."""
    job_id: str = Field(..., description="Unique job identifier")
    status: str = Field(..., description="Job status")
    download_url: Optional[str] = Field(None, description="URL to download the PPTX")
    error: Optional[str] = Field(None, description="Error message if failed")


class JobStatus(BaseModel):
    """Status of a generation job."""
    job_id: str
    status: str  # queued, processing, completed, failed
    progress: int = Field(default=0, ge=0, le=100)
    download_url: Optional[str] = None
    error: Optional[str] = None
    created_at: Optional[str] = None
    completed_at: Optional[str] = None
