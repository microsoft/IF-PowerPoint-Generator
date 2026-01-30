"""
Azure Functions API endpoints for PPT Generator Service.
"""
import azure.functions as func
import logging
import json
import os
import re
from datetime import datetime, timezone
from typing import Optional

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

from src.services import (
    BlobStorageService,
    CosmosService,
    TemplateIntrospectionService,
    ServiceBusService,
    SQLTelemetryService
)
from src.models import (
    GenerationRequest,
    JobMessage,
    BrandConfig,
    GenerationAcceptedResponse,
    JobStatusResponse,
    JobStatus
)
import uuid

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

logger = logging.getLogger(__name__)

# Initialize services
blob_storage = BlobStorageService()
cosmos = CosmosService()
template_introspection = TemplateIntrospectionService(cosmos)
servicebus = ServiceBusService()
sql_telemetry = SQLTelemetryService()

# Template ID validation pattern: lowercase alphanumeric, hyphens, underscores
VALID_TEMPLATE_ID_PATTERN = re.compile(r'^[a-z0-9][a-z0-9_-]*[a-z0-9]$|^[a-z0-9]$')
MAX_TEMPLATE_ID_LENGTH = 64


def sanitize_template_id(raw_name: str) -> str:
    """
    Sanitize a filename into a valid template ID.
    """
    # Remove .pptx extension if present
    name = raw_name.lower().replace(".pptx", "")
    # Replace spaces with hyphens
    name = name.replace(" ", "-")
    # Remove any characters that aren't alphanumeric, hyphen, or underscore
    name = re.sub(r'[^a-z0-9_-]', '', name)
    # Remove leading/trailing hyphens or underscores
    name = name.strip('-_')
    # Collapse multiple hyphens/underscores
    name = re.sub(r'[-_]+', '-', name)
    # Truncate to max length
    name = name[:MAX_TEMPLATE_ID_LENGTH]
    # Final strip in case truncation left trailing hyphen
    return name.strip('-_')


def validate_template_id(template_id: str) -> tuple:
    """Validate a template ID meets requirements."""
    if not template_id:
        return False, "Template ID cannot be empty"
    if len(template_id) > MAX_TEMPLATE_ID_LENGTH:
        return False, f"Template ID must be {MAX_TEMPLATE_ID_LENGTH} characters or less"
    if not VALID_TEMPLATE_ID_PATTERN.match(template_id):
        return False, "Template ID must be lowercase alphanumeric with hyphens/underscores"
    return True, ""


# ============================================
# HTTP Endpoints
# ============================================

@app.route(route="presentations/generate", methods=["POST"])
async def generate_presentation(req: func.HttpRequest) -> func.HttpResponse:
    """
    POST /api/v1/presentations/generate

    Accepts a presentation generation request, queues it for processing,
    and returns a job ID for status tracking.
    """
    try:
        # Parse and validate request
        try:
            body = req.get_json()
        except ValueError:
            return func.HttpResponse(
                json.dumps({"error": "Invalid JSON body"}),
                status_code=400,
                mimetype="application/json"
            )

        try:
            request = GenerationRequest(**body)
        except Exception as e:
            return func.HttpResponse(
                json.dumps({"error": f"Validation failed: {str(e)}"}),
                status_code=400,
                mimetype="application/json"
            )

        # Generate job ID
        job_id = uuid.uuid4()
        logger.info(f"Received generation request, assigned jobId: {job_id}")

        # Check cache for similar request
        content_hash = CosmosService.generate_content_hash(body)
        cached = await cosmos.check_cache(content_hash)

        if cached:
            logger.info(f"Cache hit for content hash {content_hash[:16]}...")
            return func.HttpResponse(
                json.dumps({
                    "jobId": str(job_id),
                    "status": "completed",
                    "downloadUrl": cached.get("outputUrl"),
                    "metadata": {
                        "fromCache": True,
                        "templateUsed": cached.get("templateUsed"),
                        "slideCount": cached.get("slideCount")
                    }
                }),
                status_code=200,
                mimetype="application/json"
            )

        # Apply default brand config if not provided
        brand_config = request.brandConfig or BrandConfig()

        # Create job in Cosmos
        await cosmos.create_job(str(job_id), body)

        # Log to SQL telemetry
        await sql_telemetry.log_request(str(job_id), body)

        # Prepare message for Service Bus
        job_message = JobMessage(
            jobId=job_id,
            requestId=request.request_id,
            requestorMetadata=request.requestorMetadata,
            brandConfig=brand_config,
            presentationContext=request.presentationContext,
            dataCollections=request.data_collection,
            callbackUrl=request.callbackUrl
        )

        # Queue the job (use by_alias=True to serialize with camelCase field names)
        await servicebus.send_job(job_message.model_dump(by_alias=True, mode='json'))

        # Return accepted response
        response = GenerationAcceptedResponse(
            jobId=job_id,
            status=JobStatus.QUEUED,
            statusUrl=f"/api/v1/presentations/status/{job_id}",
            estimatedCompletionSeconds=60
        )

        return func.HttpResponse(
            response.model_dump_json(),
            status_code=202,
            mimetype="application/json"
        )

    except Exception as e:
        logger.exception(f"Error processing generation request: {e}")
        return func.HttpResponse(
            json.dumps({"error": "Internal server error", "message": str(e)}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="presentations/status/{job_id}", methods=["GET"])
async def get_job_status(req: func.HttpRequest) -> func.HttpResponse:
    """
    GET /api/v1/presentations/status/{job_id}

    Returns the current status of a presentation generation job.
    """
    try:
        job_id = req.route_params.get("job_id")
        logger.info(f"Status request for job_id: {job_id}")

        if not job_id:
            return func.HttpResponse(
                json.dumps({"error": "job_id is required"}),
                status_code=400,
                mimetype="application/json"
            )

        # Get job from Cosmos
        job = await cosmos.get_job(job_id)
        logger.info(f"Cosmos returned job: {job is not None}")

        if not job:
            logger.warning(f"Job {job_id} not found in Cosmos")
            return func.HttpResponse(
                json.dumps({"error": "Job not found"}),
                status_code=404,
                mimetype="application/json"
            )

        # Build response
        response = JobStatusResponse(
            jobId=uuid.UUID(job_id) if isinstance(job_id, str) else job_id,
            status=JobStatus(job.get("status", "queued")),
            stage=job.get("currentStage"),
            progress=job.get("progress", 0),
            startedAt=job.get("processingStartedAt"),
            completedAt=job.get("completedAt"),
            downloadUrl=job.get("downloadUrl"),
            expiresAt=job.get("expiresAt"),
            metadata=job.get("metadata"),
            warnings=job.get("warnings", []),
            error=job.get("error")
        )

        return func.HttpResponse(
            response.model_dump_json(),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logger.exception(f"Error getting job status: {e}")
        return func.HttpResponse(
            json.dumps({"error": "Internal server error", "message": str(e)}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="templates", methods=["GET"])
async def list_templates(req: func.HttpRequest) -> func.HttpResponse:
    """
    GET /api/v1/templates

    Returns a list of available presentation templates.
    """
    try:
        templates = await blob_storage.list_active_templates()

        # Return summary info only
        template_list = [
            {
                "templateId": t.get("templateId"),
                "name": t.get("name"),
                "description": t.get("description"),
                "useCases": t.get("useCases", []),
                "audienceTypes": t.get("audienceTypes", []),
                "bestFor": t.get("bestFor")
            }
            for t in templates
        ]

        return func.HttpResponse(
            json.dumps({"templates": template_list, "count": len(template_list)}),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logger.exception(f"Error listing templates: {e}")
        return func.HttpResponse(
            json.dumps({"error": "Internal server error", "message": str(e)}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="templates/{template_id}", methods=["GET"])
async def get_template(req: func.HttpRequest) -> func.HttpResponse:
    """
    GET /api/v1/templates/{template_id}

    Returns detailed metadata for a specific template.
    """
    try:
        template_id = req.route_params.get("template_id")

        if not template_id:
            return func.HttpResponse(
                json.dumps({"error": "template_id is required"}),
                status_code=400,
                mimetype="application/json"
            )

        metadata = await blob_storage.get_template_metadata(template_id)

        if not metadata:
            return func.HttpResponse(
                json.dumps({"error": "Template not found"}),
                status_code=404,
                mimetype="application/json"
            )

        return func.HttpResponse(
            json.dumps(metadata),
            status_code=200,
            mimetype="application/json"
        )

    except Exception as e:
        logger.exception(f"Error getting template: {e}")
        return func.HttpResponse(
            json.dumps({"error": "Internal server error", "message": str(e)}),
            status_code=500,
            mimetype="application/json"
        )


@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """
    GET /api/v1/health
    Health check endpoint.
    """
    return func.HttpResponse(
        json.dumps({
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "service": "ppt-generator-api"
        }),
        status_code=200,
        mimetype="application/json"
    )


# ============================================
# Timer Trigger: Poll for new templates
# Replaces blob trigger due to managed identity issues with custom connections
# ============================================
@app.timer_trigger(
    arg_name="timer",
    schedule="0 */1 * * * *"  # Every 1 minute
)
async def poll_for_templates(timer: func.TimerRequest):
    """
    Timer trigger that polls for new PowerPoint templates.
    Runs every minute to check for new/modified templates and introspects them.
    Also cleans up orphaned metadata for deleted templates.
    """
    # Detailed startup logging for debugging
    logger.info("=" * 50)
    logger.info("TIMER TRIGGER STARTED: poll_for_templates")
    logger.info(f"Timer past due: {timer.past_due}")
    logger.info(f"Timer schedule status: {timer.schedule_status}")
    logger.info("=" * 50)

    storage_account = os.environ.get("STORAGE_ACCOUNT_NAME")
    if not storage_account:
        logger.error("STORAGE_ACCOUNT_NAME not configured")
        return

    logger.info(f"Polling for new templates from storage account: {storage_account}")

    try:
        # Use managed identity to connect to storage
        logger.info("Creating DefaultAzureCredential...")
        credential = DefaultAzureCredential()
        logger.info("DefaultAzureCredential created successfully")

        account_url = f"https://{storage_account}.blob.core.windows.net"
        logger.info(f"Connecting to blob storage: {account_url}")
        blob_service = BlobServiceClient(
            account_url=account_url,
            credential=credential
        )
        logger.info("BlobServiceClient created successfully")

        container = blob_service.get_container_client("ppt-templates")
        logger.info("Got container client for ppt-templates")

        # Track all valid template IDs found in this poll
        valid_template_ids = set()
        templates_found = 0
        templates_processed = 0

        # Collect all blobs first for efficient lookup
        logger.info("Listing blobs in ppt-templates container...")
        try:
            all_blobs = {blob.name: blob for blob in container.list_blobs()}
            logger.info(f"Successfully listed {len(all_blobs)} blobs in container")
        except Exception as list_error:
            logger.exception(f"FAILED to list blobs: {list_error}")
            raise

        for blob_name, blob in all_blobs.items():
            # Look for template.pptx files in subfolders
            if blob_name.endswith("/template.pptx"):
                templates_found += 1
                template_id = blob_name.split("/")[0]
                valid_template_ids.add(template_id)
                metadata_path = f"{template_id}/metadata.json"

                # Check if metadata needs updating
                needs_processing = False
                metadata_blob = container.get_blob_client(metadata_path)

                if metadata_path not in all_blobs:
                    logger.info(f"No metadata found for template: {template_id}")
                    needs_processing = True
                else:
                    # Check if template is newer than metadata
                    template_modified = blob.last_modified
                    metadata_modified = all_blobs[metadata_path].last_modified
                    if template_modified > metadata_modified:
                        logger.info(f"Template {template_id} modified after metadata, reprocessing")
                        needs_processing = True

                if needs_processing:
                    logger.info(f"Processing template: {template_id}")
                    await process_template(container, blob_name, template_id)
                    templates_processed += 1

            # Also check for .pptx files in root (direct uploads)
            elif blob_name.endswith(".pptx") and "/" not in blob_name:
                templates_found += 1
                raw_template_id = blob_name.replace(".pptx", "")
                template_id = sanitize_template_id(raw_template_id)

                is_valid, error_msg = validate_template_id(template_id)
                if not is_valid:
                    logger.error(f"Invalid template ID from filename '{raw_template_id}': {error_msg}")
                    continue

                valid_template_ids.add(template_id)
                metadata_path = f"{template_id}/metadata.json"

                # Check if metadata needs updating
                needs_processing = False

                if metadata_path not in all_blobs:
                    logger.info(f"No metadata found for root template: {template_id}")
                    needs_processing = True
                else:
                    # Check if template is newer than metadata
                    template_modified = blob.last_modified
                    metadata_modified = all_blobs[metadata_path].last_modified
                    if template_modified > metadata_modified:
                        logger.info(f"Root template {template_id} modified after metadata, reprocessing")
                        needs_processing = True

                if needs_processing:
                    logger.info(f"Processing root template: {template_id}")
                    await process_template(container, blob_name, template_id)
                    templates_processed += 1

        # Sync metadata.json files to Cosmos if versions differ
        metadata_synced = 0
        for blob_name, blob in all_blobs.items():
            if blob_name.endswith("/metadata.json"):
                template_id = blob_name.split("/")[0]
                if template_id in valid_template_ids:
                    try:
                        # Read blob metadata to get version
                        blob_client = container.get_blob_client(blob_name)
                        blob_metadata_bytes = blob_client.download_blob().readall()
                        blob_metadata = json.loads(blob_metadata_bytes)
                        blob_version = blob_metadata.get("version", "0.0.0")

                        # Get Cosmos version
                        cosmos_template = await cosmos.get_template(template_id)
                        cosmos_version = cosmos_template.get("version", "0.0.0") if cosmos_template else None

                        # Sync if versions differ or template doesn't exist in Cosmos
                        if cosmos_version != blob_version:
                            logger.info(f"Version mismatch for {template_id}: blob={blob_version}, cosmos={cosmos_version}. Syncing...")
                            await sync_metadata_to_cosmos(container, template_id)
                            metadata_synced += 1
                        else:
                            logger.debug(f"Template {template_id} version {blob_version} already in sync")
                    except Exception as e:
                        logger.warning(f"Failed to check/sync metadata for {template_id}: {e}")

        # Clean up orphaned metadata in Cosmos DB
        # (templates that were deleted from blob storage)
        try:
            await cleanup_orphaned_templates(valid_template_ids)
        except Exception as e:
            logger.warning(f"Error cleaning up orphaned templates: {e}")

        logger.info(f"Poll complete. Found {templates_found} templates, {templates_processed} processed, {metadata_synced} metadata synced.")
        logger.info("=" * 50)
        logger.info("TIMER TRIGGER COMPLETED SUCCESSFULLY")
        logger.info("=" * 50)

    except Exception as e:
        logger.error("=" * 50)
        logger.error("TIMER TRIGGER FAILED")
        logger.error(f"Exception type: {type(e).__name__}")
        logger.error(f"Exception message: {str(e)}")
        logger.exception(f"Full exception details:")
        logger.error("=" * 50)


async def cleanup_orphaned_templates(valid_template_ids: set):
    """Remove templates from Cosmos that no longer exist in blob storage."""
    try:
        logger.info(f"Cleanup: Valid template IDs in blob storage: {valid_template_ids}")

        # Get all templates from Cosmos
        cosmos_templates = await cosmos.list_templates()
        logger.info(f"Cleanup: Found {len(cosmos_templates)} templates in Cosmos")

        deleted_count = 0
        for template in cosmos_templates:
            template_id = template.get("templateId") or template.get("id")
            logger.info(f"Cleanup: Checking template '{template_id}' - in valid set: {template_id in valid_template_ids}")

            if template_id and template_id not in valid_template_ids:
                logger.info(f"Cleanup: Removing orphaned template from Cosmos: {template_id}")
                await cosmos.delete_template(template_id)
                deleted_count += 1

        logger.info(f"Cleanup complete: Deleted {deleted_count} orphaned templates")
    except Exception as e:
        logger.exception(f"Could not clean up orphaned templates: {e}")


async def sync_metadata_to_cosmos(container, template_id: str):
    """Read metadata.json from blob and sync to Cosmos DB."""
    try:
        metadata_path = f"{template_id}/metadata.json"
        blob_client = container.get_blob_client(metadata_path)
        metadata_bytes = blob_client.download_blob().readall()
        metadata = json.loads(metadata_bytes)

        # Save to Cosmos
        await template_introspection.save_to_cosmos(template_id, metadata)
        logger.info(f"Synced metadata to Cosmos: {template_id}")
    except Exception as e:
        logger.exception(f"Error syncing metadata for {template_id}: {e}")


# ============================================
# NOTE: Service Bus processing is handled by the V3 Orchestrator
# The orchestrator Container App consumes from the ppt-generation-jobs queue
# and runs a single Assistants API call with local chart rendering.
# ============================================


async def process_template(container, blob_name: str, template_id: str) -> None:
    """
    Process a single template: introspect and generate metadata.
    If template is in root (not in folder), copies it to {template_id}/template.pptx
    """
    try:
        # Download template bytes
        blob_client = container.get_blob_client(blob_name)
        template_bytes = blob_client.download_blob().readall()
        logger.info(f"Downloaded template {template_id}: {len(template_bytes)} bytes")

        # If this is a root file (not already in a folder), copy to proper structure
        if "/" not in blob_name:
            target_path = f"{template_id}/template.pptx"
            target_blob = container.get_blob_client(target_path)
            target_blob.upload_blob(template_bytes, overwrite=True)
            logger.info(f"Copied root template to: {target_path}")

            # Optionally delete the original root file to keep things clean
            try:
                blob_client.delete_blob()
                logger.info(f"Deleted original root file: {blob_name}")
            except Exception as e:
                logger.warning(f"Could not delete original root file {blob_name}: {e}")

        # Introspect the template
        metadata = template_introspection.introspect_template(template_bytes, template_id)
        logger.info(f"Introspection complete for {template_id}. Found {len(metadata['slideLayouts'])} layouts")

        # Upload metadata.json to blob storage
        await blob_storage.upload_template_metadata(template_id, metadata)
        logger.info(f"Metadata uploaded to blob: {template_id}/metadata.json")

        # Save to Cosmos DB for fast retrieval
        await template_introspection.save_to_cosmos(template_id, metadata)
        logger.info(f"Metadata cached in Cosmos DB: {template_id}")

        logger.info(f"Template processing complete: {template_id}")

    except Exception as e:
        logger.exception(f"Error processing template {template_id}: {e}")
