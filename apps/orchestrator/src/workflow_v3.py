"""
V3 Workflow - Simplified Assistants API Pipeline

This is the new simplified pipeline that:
1. Takes data in
2. Sends to Assistant (single call)
3. Gets back slides + chart blueprints (JSON specifications)
4. Renders blueprints to PNG locally using ChartRenderer
5. Assembles PPT
6. Done

No LangGraph. No multi-node orchestration. No local parsing.
Blueprint approach: Assistant returns JSON specs, orchestrator renders charts.
"""
import logging
import os
from pathlib import Path
from typing import Dict, Any, Optional, List

from .services import (
    settings,
    cosmos_service,
    blob_service,
    assistants_service
)
from .ppt_assembler import assemble_presentation
from .chart_renderer import ChartRenderer

logger = logging.getLogger(__name__)

# Load system prompt
PROMPT_PATH = Path(__file__).parent / "prompts" / "system_prompt.md"


def load_system_prompt() -> str:
    """Load the system prompt from file."""
    if PROMPT_PATH.exists():
        return PROMPT_PATH.read_text()
    else:
        logger.warning(f"System prompt not found at {PROMPT_PATH}, using default")
        return "You are a presentation generator. Analyze data and create charts."


async def run_pipeline_v3(
    job_id: str,
    request_id: str,
    presentation_context: Dict[str, Any],
    data_collections: List[Dict[str, Any]],
    brand_config: Dict[str, Any] = None,
    callback_url: str = None,
    template_id: str = None
) -> Dict[str, Any]:
    """
    Run the v3 presentation generation pipeline.

    This is dramatically simpler than v2:
    1. Single Assistant call does all the thinking
    2. Assistant returns chart blueprints (JSON specifications)
    3. ChartRenderer renders blueprints locally using Plotly
    4. We assemble the PPT from slides + rendered charts

    Args:
        job_id: Unique job identifier
        request_id: Request identifier for tracking
        presentation_context: Title, audience, etc.
        data_collections: List of data to visualize
        brand_config: Brand colors and styling
        callback_url: Optional webhook URL
        template_id: Optional template to use

    Returns:
        Final state with download_url
    """
    logger.info(f"[{job_id}] Starting v3 pipeline")

    brand_config = brand_config or {}
    presentation_context = presentation_context or {}
    title = presentation_context.get("title", "Business Presentation")
    audience = presentation_context.get("audience", "executives")

    try:
        # Step 1: Update status - Starting
        cosmos_service.update_job(job_id, {
            "currentStage": "initializing",
            "progress": 10,
            "status": "processing",
            "version": "v3"
        })

        # Step 2: Load template FIRST - ALWAYS use a template to preserve branding
        # This must happen BEFORE the Assistant call so template logs always appear
        template_bytes = None
        template_to_use = template_id

        # If no template specified, select default from Cosmos DB
        if not template_to_use:
            logger.info(f"[{job_id}] No template specified, selecting default from Cosmos DB")
            try:
                templates = cosmos_service.list_templates()
                if templates:
                    # Try to find a default template
                    default_template = next((t for t in templates if t.get("isDefault", False)), None)
                    if not default_template:
                        # Use the first available template
                        default_template = templates[0]

                    template_to_use = default_template.get("id")
                    logger.info(f"[{job_id}] Selected template: {template_to_use} (name: {default_template.get('name', 'N/A')})")
                else:
                    logger.error(f"[{job_id}] No templates available in Cosmos DB - branding will be missing!")
            except Exception as e:
                logger.error(f"[{job_id}] Could not retrieve templates from Cosmos: {e}")

        # Download template and metadata if we have one
        template_metadata = None
        if template_to_use:
            try:
                template_bytes = blob_service.download_template(template_to_use)
                logger.info(f"[{job_id}] Loaded template: {template_to_use} ({len(template_bytes)} bytes)")
            except Exception as e:
                logger.error(f"[{job_id}] Could not load template {template_to_use}: {e}")
                template_bytes = None

            # Also fetch template metadata for dynamic layout selection
            try:
                template_metadata = blob_service.get_template_metadata(template_to_use)
                if template_metadata:
                    logger.info(f"[{job_id}] Loaded template metadata with {len(template_metadata.get('layoutSelectionGuide', {}))} layout mappings")
                else:
                    logger.warning(f"[{job_id}] No metadata found for template {template_to_use}, using default layout indices")
            except Exception as e:
                logger.warning(f"[{job_id}] Could not load template metadata: {e}")
                template_metadata = None

        # Log template status for debugging
        if template_bytes:
            logger.info(f"[{job_id}] Template ready: {len(template_bytes)} bytes")
        else:
            logger.error(f"[{job_id}] WARNING: No template loaded - presentation will have NO BRANDING!")

        # Step 3: Load system prompt and get/create assistant
        logger.info(f"[{job_id}] Loading system prompt and preparing assistant")
        system_prompt = load_system_prompt()

        # Replace brand color placeholders in prompt
        primary_color = brand_config.get("primaryColor", brand_config.get("primary_color", "#003366"))
        secondary_color = brand_config.get("secondaryColor", brand_config.get("secondary_color", "#50E6FF"))
        system_prompt = system_prompt.replace("{primary_color}", primary_color)
        system_prompt = system_prompt.replace("{secondary_color}", secondary_color)

        assistant_id = assistants_service.get_or_create_assistant(system_prompt)

        cosmos_service.update_job(job_id, {
            "currentStage": "analyzing_data",
            "progress": 20
        })

        # Step 4: Call Assistant - This is where ALL the magic happens
        logger.info(f"[{job_id}] Calling Assistant API (this may take a minute)...")

        response_json, blueprints = assistants_service.generate_presentation(
            assistant_id=assistant_id,
            title=title,
            audience=audience,
            data_collections=data_collections,
            brand_config=brand_config
        )

        logger.info(f"[{job_id}] Assistant returned {len(response_json.get('slides', []))} slides")
        logger.info(f"[{job_id}] Chart blueprints received: {len(blueprints)}")

        cosmos_service.update_job(job_id, {
            "currentStage": "creating_slides",
            "progress": 60
        })

        # Step 5: Render chart blueprints locally using Plotly
        logger.info(f"[{job_id}] Rendering {len(blueprints)} chart blueprints...")

        chart_renderer = ChartRenderer(brand_config=brand_config)
        chart_files = chart_renderer.render_all(blueprints)

        logger.info(f"[{job_id}] Rendered {len(chart_files)} chart images")

        cosmos_service.update_job(job_id, {
            "currentStage": "build",
            "progress": 70
        })

        # Step 6: Assemble PowerPoint
        logger.info(f"[{job_id}] Assembling PowerPoint")

        pptx_bytes = assemble_presentation(
            slides=response_json.get("slides", []),
            chart_files=chart_files,
            template_bytes=template_bytes,
            template_metadata=template_metadata,
            presentation_title=response_json.get("presentation_title", title),
            presentation_subtitle=response_json.get("presentation_subtitle")
        )

        logger.info(f"[{job_id}] PowerPoint assembled: {len(pptx_bytes)} bytes")

        cosmos_service.update_job(job_id, {
            "currentStage": "finalizing",
            "progress": 90
        })

        # Step 7: Upload to blob storage
        blob_path = blob_service.upload_output(job_id, pptx_bytes)
        download_url = blob_service.generate_sas_url(job_id)

        logger.info(f"[{job_id}] Uploaded to: {blob_path}")
        logger.info(f"[{job_id}] Download URL generated")

        # Step 8: Update final status
        metadata = response_json.get("metadata", {})
        cosmos_service.update_job(job_id, {
            "currentStage": "completed",
            "status": "completed",
            "progress": 100,
            "downloadUrl": download_url,
            "slideCount": metadata.get("total_slides", len(response_json.get("slides", []))),
            "chartsGenerated": metadata.get("charts_generated", len(chart_files)),
            "narrativeArc": metadata.get("narrative_arc", "")
        })

        logger.info(f"[{job_id}] Pipeline completed successfully")

        return {
            "job_id": job_id,
            "status": "completed",
            "download_url": download_url,
            "slides": response_json.get("slides", []),
            "metadata": metadata
        }

    except Exception as e:
        logger.exception(f"[{job_id}] Pipeline failed: {e}")

        cosmos_service.update_job(job_id, {
            "currentStage": "failed",
            "status": "failed",
            "errorMessage": str(e)
        })

        cosmos_service.log_error(
            job_id=job_id,
            error_type="PIPELINE_V3_ERROR",
            error_message=str(e),
            node_name="workflow_v3"
        )

        return {
            "job_id": job_id,
            "status": "failed",
            "error": str(e)
        }


# For backwards compatibility during migration
run_pipeline = run_pipeline_v3
