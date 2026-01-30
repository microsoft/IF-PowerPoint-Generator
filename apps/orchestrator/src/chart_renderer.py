"""
Chart Renderer - Renders ChartBlueprint to PNG using Plotly + Kaleido

This module provides local chart rendering, replacing the Code Interpreter approach.
The Assistant returns JSON blueprints; this module renders them to PNG images.

Benefits:
- Reliable: No dependency on Code Interpreter package availability
- Fast: No code execution in Assistant
- Consistent: Centralized styling control
- Debuggable: Blueprint JSON is inspectable
"""
import logging
from io import BytesIO
from typing import Dict, List, Optional

import plotly.graph_objects as go
import plotly.io as pio

from .models.v3 import ChartBlueprint, ChartType, ValueFormat, LegendPosition, SeriesData

logger = logging.getLogger(__name__)

# Chart dimensions matching system prompt requirements
CHART_WIDTH = 1920
CHART_HEIGHT = 1080
CHART_SCALE = 2  # Results in 3840x2160 at 300 DPI equivalent

# Default color palette (Corporate-inspired)
DEFAULT_COLORS = [
    "#003366",  # Primary (dark blue)
    "#50E6FF",  # Secondary (light blue)
    "#6B7280",  # Tertiary (gray-500)
    "#9CA3AF",  # Quaternary (gray-400)
    "#10B981",  # Positive (green)
    "#EF4444",  # Negative (red)
    "#F59E0B",  # Highlight (amber)
    "#8B5CF6",  # Purple
]


class ChartRenderer:
    """
    Renders ChartBlueprint objects to PNG images using Plotly.

    Usage:
        renderer = ChartRenderer(brand_config={"primaryColor": "#003366"})
        png_bytes = renderer.render(blueprint)
        all_charts = renderer.render_all(blueprints)  # Returns dict of filename -> bytes
    """

    def __init__(self, brand_config: Optional[Dict] = None):
        """
        Initialize the renderer with brand colors.

        Args:
            brand_config: Dict with primaryColor, secondaryColor keys
        """
        self.brand_config = brand_config or {}
        self.primary_color = self.brand_config.get("primaryColor",
                             self.brand_config.get("primary_color", "#003366"))
        self.secondary_color = self.brand_config.get("secondaryColor",
                               self.brand_config.get("secondary_color", "#50E6FF"))
        self.colors = self._build_color_palette()

    def _build_color_palette(self) -> List[str]:
        """Build color palette with brand colors first."""
        return [
            self.primary_color,
            self.secondary_color,
            "#6B7280",  # Gray-500
            "#9CA3AF",  # Gray-400
            "#10B981",  # Green
            "#EF4444",  # Red
            "#F59E0B",  # Amber
            "#8B5CF6",  # Purple
        ]

    def render(self, blueprint: ChartBlueprint) -> bytes:
        """
        Render a single blueprint to PNG bytes.

        Args:
            blueprint: ChartBlueprint object defining the chart

        Returns:
            PNG image as bytes
        """
        logger.info(f"Rendering chart: {blueprint.chart_id} ({blueprint.chart_type})")

        # Create figure based on chart type
        fig = self._create_figure(blueprint)

        # Apply common styling
        self._apply_common_styling(fig, blueprint)

        # Export to PNG
        return self._export_png(fig)

    def render_all(self, blueprints: List[ChartBlueprint]) -> Dict[str, bytes]:
        """
        Render all blueprints to a dictionary of filename -> PNG bytes.

        Args:
            blueprints: List of ChartBlueprint objects

        Returns:
            Dict mapping chart filenames (e.g., "chart_1.png") to PNG bytes
        """
        result = {}
        for blueprint in blueprints:
            filename = f"{blueprint.chart_id}.png"
            try:
                result[filename] = self.render(blueprint)
                logger.info(f"Rendered {filename}: {len(result[filename])} bytes")
            except Exception as e:
                logger.error(f"Failed to render {filename}: {e}")
                # Continue with other charts
        return result

    def _create_figure(self, bp: ChartBlueprint) -> go.Figure:
        """Create Plotly figure based on chart type."""
        chart_type = bp.chart_type
        if isinstance(chart_type, str):
            chart_type = ChartType(chart_type)

        creators = {
            ChartType.HORIZONTAL_BAR: self._create_horizontal_bar,
            ChartType.GROUPED_BAR: self._create_grouped_bar,
            ChartType.STACKED_BAR: self._create_stacked_bar,
            ChartType.DONUT: self._create_donut,
            ChartType.LINE: self._create_line,
            ChartType.AREA: self._create_area,
            ChartType.WATERFALL: self._create_waterfall,
            ChartType.DIVERGING_BAR: self._create_diverging_bar,
        }

        creator = creators.get(chart_type)
        if not creator:
            logger.warning(f"Unknown chart type: {chart_type}, using horizontal bar")
            creator = self._create_horizontal_bar

        return creator(bp)

    def _get_colors(self, bp: ChartBlueprint, count: int) -> List[str]:
        """Get colors for chart, using blueprint colors or defaults."""
        if bp.colors:
            return bp.colors[:count] + self.colors[len(bp.colors):count]
        return self.colors[:count]

    def _format_value(self, value: float, format_type: ValueFormat) -> str:
        """Format a numeric value based on format type."""
        if isinstance(format_type, str):
            format_type = ValueFormat(format_type)

        if format_type == ValueFormat.PERCENT:
            return f"{value:.1f}%"
        elif format_type == ValueFormat.CURRENCY:
            return f"${value:,.0f}"
        elif format_type == ValueFormat.CURRENCY_K:
            return f"${value/1000:.1f}K"
        elif format_type == ValueFormat.CURRENCY_M:
            return f"${value/1000000:.2f}M"
        else:
            return f"{value:,.1f}"

    def _create_horizontal_bar(self, bp: ChartBlueprint) -> go.Figure:
        """Create horizontal bar chart."""
        categories = bp.categories.copy()
        values = bp.series[0].values.copy()

        # Sort descending if requested
        if bp.sort_descending:
            sorted_data = sorted(zip(values, categories), reverse=True)
            values, categories = zip(*sorted_data) if sorted_data else ([], [])
            values, categories = list(values), list(categories)

        # Reverse for horizontal bar (top to bottom display)
        categories = categories[::-1]
        values = values[::-1]

        colors = self._get_colors(bp, len(categories))

        # Format text labels
        text_labels = [self._format_value(v, bp.value_format) for v in values]

        fig = go.Figure(go.Bar(
            x=values,
            y=categories,
            orientation='h',
            marker_color=colors[0] if len(set(colors)) == 1 else colors[:len(categories)],
            text=text_labels if bp.show_data_labels else None,
            textposition='outside',
            textfont=dict(size=32),  # Data labels
        ))

        return fig

    def _create_grouped_bar(self, bp: ChartBlueprint) -> go.Figure:
        """Create grouped bar chart for comparisons (e.g., current vs target)."""
        fig = go.Figure()
        colors = self._get_colors(bp, len(bp.series))

        for idx, series in enumerate(bp.series):
            text_labels = [self._format_value(v, bp.value_format) for v in series.values]

            fig.add_trace(go.Bar(
                name=series.name,
                x=bp.categories,
                y=series.values,
                marker_color=series.color or colors[idx],
                text=text_labels if bp.show_data_labels else None,
                textposition='outside',
                textfont=dict(size=32),  # Data labels
            ))

        fig.update_layout(barmode='group')
        return fig

    def _create_stacked_bar(self, bp: ChartBlueprint) -> go.Figure:
        """Create stacked bar chart for composition."""
        fig = go.Figure()
        colors = self._get_colors(bp, len(bp.series))

        for idx, series in enumerate(bp.series):
            text_labels = [self._format_value(v, bp.value_format) for v in series.values]

            fig.add_trace(go.Bar(
                name=series.name,
                x=bp.categories,
                y=series.values,
                marker_color=series.color or colors[idx],
                text=text_labels if bp.show_data_labels else None,
                textposition='inside',
                textfont=dict(size=24, color='white'),  # Stacked bar labels
            ))

        fig.update_layout(barmode='stack')
        return fig

    def _create_donut(self, bp: ChartBlueprint) -> go.Figure:
        """Create donut chart with center annotation."""
        values = bp.series[0].values
        colors = self._get_colors(bp, len(bp.categories))

        fig = go.Figure(go.Pie(
            labels=bp.categories,
            values=values,
            hole=0.6,
            marker_colors=colors[:len(bp.categories)],
            textinfo='label+percent' if bp.show_data_labels else 'label',
            textposition='outside',
            textfont=dict(size=32),  # Data labels
            pull=[0.02] * len(values),  # Slight separation
        ))

        # Add center annotation if provided
        if bp.center_value or bp.center_text:
            center_content = ""
            if bp.center_value:
                center_content = f"<b>{bp.center_value}</b>"
            if bp.center_text:
                center_content += f"<br>{bp.center_text}" if center_content else bp.center_text

            fig.add_annotation(
                text=center_content,
                x=0.5, y=0.5,
                font=dict(size=48, color=self.primary_color),  # Donut center
                showarrow=False,
                xref="paper", yref="paper",
            )

        return fig

    def _create_line(self, bp: ChartBlueprint) -> go.Figure:
        """Create line chart for trends."""
        fig = go.Figure()
        colors = self._get_colors(bp, len(bp.series))

        for idx, series in enumerate(bp.series):
            fig.add_trace(go.Scatter(
                x=bp.categories,
                y=series.values,
                mode='lines+markers+text' if bp.show_data_labels else 'lines+markers',
                name=series.name,
                line=dict(color=series.color or colors[idx], width=3),
                marker=dict(size=8),
                text=[self._format_value(v, bp.value_format) for v in series.values] if bp.show_data_labels else None,
                textposition='top center',
                textfont=dict(size=32),  # Data labels
            ))

        return fig

    def _create_area(self, bp: ChartBlueprint) -> go.Figure:
        """Create area chart for trends with fill."""
        fig = go.Figure()
        colors = self._get_colors(bp, len(bp.series))

        for idx, series in enumerate(bp.series):
            color = series.color or colors[idx]
            fig.add_trace(go.Scatter(
                x=bp.categories,
                y=series.values,
                mode='lines',
                name=series.name,
                line=dict(color=color, width=2),
                fill='tozeroy' if idx == 0 else 'tonexty',
                fillcolor=color.replace(')', ', 0.3)').replace('rgb', 'rgba') if 'rgb' in color else color + '4D',
            ))

        return fig

    def _create_waterfall(self, bp: ChartBlueprint) -> go.Figure:
        """Create waterfall chart for changes/savings analysis."""
        values = bp.series[0].values
        measures = bp.measures or ['relative'] * len(values)

        # Ensure first is absolute and last is total
        if measures[0] != 'absolute':
            measures[0] = 'absolute'
        if measures[-1] != 'total':
            measures[-1] = 'total'

        text_labels = [self._format_value(v, bp.value_format) for v in values]

        fig = go.Figure(go.Waterfall(
            x=bp.categories,
            y=values,
            measure=measures,
            text=text_labels if bp.show_data_labels else None,
            textposition='outside',
            textfont=dict(size=32),  # Data labels
            increasing=dict(marker_color="#10B981"),  # Green
            decreasing=dict(marker_color="#EF4444"),  # Red
            totals=dict(marker_color=self.primary_color),
            connector=dict(line=dict(color="#9CA3AF", width=1)),
        ))

        return fig

    def _create_diverging_bar(self, bp: ChartBlueprint) -> go.Figure:
        """Create diverging bar chart for gap analysis."""
        # Similar to horizontal bar but with positive/negative coloring
        values = bp.series[0].values
        colors = ["#10B981" if v >= 0 else "#EF4444" for v in values]

        text_labels = [self._format_value(v, bp.value_format) for v in values]

        fig = go.Figure(go.Bar(
            x=values,
            y=bp.categories[::-1],  # Reverse for top-to-bottom
            orientation='h',
            marker_color=colors[::-1],
            text=text_labels[::-1] if bp.show_data_labels else None,
            textposition='outside',
            textfont=dict(size=32),  # Data labels
        ))

        # Add zero line
        fig.add_vline(x=0, line_width=2, line_color="#374151")

        return fig

    def _apply_common_styling(self, fig: go.Figure, bp: ChartBlueprint) -> None:
        """Apply common styling to all chart types."""
        # Legend configuration
        legend_config = dict(
            orientation="h",
            yanchor="top",
            y=-0.15,
            xanchor="center",
            x=0.5,
            font=dict(size=32),  # Legend
        )

        legend_pos = bp.legend_position
        if isinstance(legend_pos, str):
            legend_pos = LegendPosition(legend_pos)

        if legend_pos == LegendPosition.RIGHT:
            legend_config = dict(
                orientation="v",
                yanchor="middle",
                y=0.5,
                xanchor="left",
                x=1.02,
                font=dict(size=32),  # Legend
            )
        elif legend_pos == LegendPosition.TOP:
            legend_config = dict(
                orientation="h",
                yanchor="bottom",
                y=1.02,
                xanchor="center",
                x=0.5,
                font=dict(size=32),  # Legend
            )
        elif legend_pos == LegendPosition.NONE:
            legend_config = dict(visible=False)

        # Hide legend for single series
        if len(bp.series) == 1 and bp.chart_type not in [ChartType.DONUT]:
            legend_config = dict(visible=False)

        fig.update_layout(
            title=dict(
                text=bp.title,
                font=dict(size=52, color="#1F2937", family="DejaVu Sans"),  # Title
                x=0.5,
                xanchor="center",
                y=0.97,
            ),
            font=dict(family="DejaVu Sans", size=38, color="#374151"),  # Base font
            plot_bgcolor="white",
            paper_bgcolor="white",
            margin=dict(l=80, r=80, t=180, b=80),
            showlegend=bp.show_legend,
            legend=legend_config,
            width=CHART_WIDTH,
            height=CHART_HEIGHT,
        )

        # Remove gridlines (or make very faint)
        fig.update_xaxes(
            showgrid=False,
            showline=True,
            linecolor="#E5E7EB",
            title_text=bp.x_axis_label,
            title_font=dict(size=24),  # Axis titles
        )
        fig.update_yaxes(
            showgrid=False,
            showline=True,
            linecolor="#E5E7EB",
            title_text=bp.y_axis_label,
            title_font=dict(size=24),  # Axis titles
        )

        # Add subtitle if present
        if bp.subtitle:
            fig.add_annotation(
                text=bp.subtitle,
                xref="paper", yref="paper",
                x=0.5, y=1.08,
                showarrow=False,
                font=dict(size=38, color="#6B7280"),  # Subtitle
                xanchor="center",
            )

    def _export_png(self, fig: go.Figure) -> bytes:
        """Export figure to PNG bytes."""
        return pio.to_image(
            fig,
            format='png',
            width=CHART_WIDTH,
            height=CHART_HEIGHT,
            scale=CHART_SCALE,
        )
