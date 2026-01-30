"""
FastAPI application for the Presentation Generator Orchestrator.

V3 Architecture - Simplified Assistants API approach:
1. Consumes messages from Azure Service Bus
2. Single Assistant call generates everything (charts + content)
3. Assembles PPT from response
4. Provides health and status endpoints
"""
import os
import json
import asyncio
import logging
from contextlib import asynccontextmanager
from typing import Dict, Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from azure.servicebus.aio import ServiceBusClient as AsyncServiceBusClient
from azure.identity.aio import DefaultAzureCredential as AsyncDefaultAzureCredential

from .workflow_v3 import run_pipeline_v3 as run_pipeline
from .services import settings, cosmos_service

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


# Global state for the consumer
consumer_task = None
shutdown_event = asyncio.Event()


async def process_message(message_body: Dict[str, Any]):
    """Process a single Service Bus message through the pipeline."""
    job_id = message_body.get("jobId") or message_body.get("job_id")
    request_id = message_body.get("requestId") or message_body.get("request_id", "unknown")

    logger.info(f"[{job_id}] Processing message")
    logger.info(f"[{job_id}] Message keys: {list(message_body.keys())}")

    try:
        # Update job status to processing
        cosmos_service.update_job(job_id, {
            "currentStage": "processing",
            "progress": 5,
            "status": "processing"
        })

        # Extract pipeline inputs - fields are at top level of message
        # Note: JobMessage sends presentationContext, brandConfig, dataCollections at top level
        presentation_context = message_body.get("presentationContext", {})
        data_collections = message_body.get("dataCollections", [])
        brand_config = message_body.get("brandConfig", {})
        callback_url = message_body.get("callbackUrl")

        logger.info(f"[{job_id}] Presentation context: {presentation_context}")
        logger.info(f"[{job_id}] Data collections count: {len(data_collections)}")

        # Run the pipeline
        final_state = await run_pipeline(
            job_id=job_id,
            request_id=request_id,
            presentation_context=presentation_context,
            data_collections=data_collections,
            brand_config=brand_config,
            callback_url=callback_url
        )

        logger.info(f"[{job_id}] Pipeline completed. Download URL: {final_state.get('download_url')}")

        # Call callback if provided
        if callback_url:
            await call_webhook(callback_url, job_id, final_state)

    except Exception as e:
        logger.error(f"[{job_id}] Pipeline failed: {e}")
        cosmos_service.update_job(job_id, {
            "currentStage": "failed",
            "errorMessage": str(e)
        })
        cosmos_service.log_error(job_id, "PIPELINE_ERROR", str(e))


async def call_webhook(callback_url: str, job_id: str, state: Dict[str, Any]):
    """Call the webhook with completion status."""
    import aiohttp

    try:
        validation_result = state.get("validation_result")
        quality_score = validation_result.quality_score if validation_result else 0

        payload = {
            "jobId": job_id,
            "status": "completed",
            "downloadUrl": state.get("download_url"),
            "qualityScore": quality_score
        }

        async with aiohttp.ClientSession() as session:
            async with session.post(callback_url, json=payload, timeout=30) as response:
                if response.status >= 400:
                    logger.warning(f"[{job_id}] Webhook returned {response.status}")
                else:
                    logger.info(f"[{job_id}] Webhook called successfully")

    except Exception as e:
        logger.error(f"[{job_id}] Webhook call failed: {e}")


async def consume_service_bus():
    """Continuously consume messages from Service Bus."""
    logger.info("Starting Service Bus consumer...")
    logger.info(f"Service Bus namespace: {settings.servicebus_namespace}")
    logger.info(f"Service Bus queue: {settings.servicebus_queue}")

    if not settings.servicebus_namespace:
        logger.error("SERVICEBUS_NAMESPACE environment variable is not set!")
        return

    credential = AsyncDefaultAzureCredential()

    try:
        logger.info("Connecting to Service Bus...")
        async with AsyncServiceBusClient(
            fully_qualified_namespace=settings.servicebus_namespace,
            credential=credential
        ) as client:
            logger.info("Connected to Service Bus, creating receiver...")
            async with client.get_queue_receiver(
                queue_name=settings.servicebus_queue,
                max_wait_time=5
            ) as receiver:
                logger.info(f"Listening on queue: {settings.servicebus_queue}")

                while not shutdown_event.is_set():
                    try:
                        messages = await receiver.receive_messages(
                            max_message_count=1,
                            max_wait_time=5
                        )

                        if messages:
                            logger.info(f"Received {len(messages)} message(s)")

                        for message in messages:
                            try:
                                # Parse message body - get bytes and decode
                                message_bytes = b''.join(message.body)
                                message_str = message_bytes.decode('utf-8')
                                logger.info(f"Message body (first 200 chars): {message_str[:200]}")

                                body = json.loads(message_str)
                                logger.info(f"Received message for job: {body.get('jobId')}")

                                # Process the message
                                await process_message(body)

                                # Complete the message
                                await receiver.complete_message(message)
                                logger.info(f"Message completed for job: {body.get('jobId')}")

                            except json.JSONDecodeError as e:
                                logger.error(f"Invalid message format: {e}")
                                logger.error(f"Raw message: {message_str[:500] if 'message_str' in locals() else 'N/A'}")
                                await receiver.dead_letter_message(
                                    message,
                                    reason="Invalid JSON",
                                    error_description=str(e)
                                )
                            except Exception as e:
                                logger.exception(f"Error processing message: {e}")
                                # Don't complete - let it retry
                                await receiver.abandon_message(message)

                    except Exception as e:
                        if not shutdown_event.is_set():
                            logger.exception(f"Error receiving messages: {e}")
                            await asyncio.sleep(5)

    except Exception as e:
        logger.exception(f"Service Bus consumer error: {e}")
        raise
    finally:
        await credential.close()
        logger.info("Service Bus consumer stopped")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle."""
    global consumer_task

    logger.info("=" * 60)
    logger.info("Starting PPT Generator Orchestrator...")
    logger.info("=" * 60)

    # Start the Service Bus consumer in the background
    try:
        consumer_task = asyncio.create_task(consume_service_bus())
        logger.info("Service Bus consumer task started")
    except Exception as e:
        logger.exception(f"Failed to start Service Bus consumer: {e}")

    yield

    # Shutdown
    logger.info("Shutting down orchestrator...")
    shutdown_event.set()

    if consumer_task:
        consumer_task.cancel()
        try:
            await consumer_task
        except asyncio.CancelledError:
            pass
    logger.info("Orchestrator shutdown complete")


# Create FastAPI app
app = FastAPI(
    title="PPT Generator Orchestrator",
    description="V3 Assistants API-based presentation generation service",
    version="3.0.0",
    lifespan=lifespan
)


# Health check models
class HealthResponse(BaseModel):
    status: str
    version: str
    service: str


class DetailedHealthResponse(HealthResponse):
    cosmos_connected: bool
    storage_connected: bool
    openai_configured: bool
    servicebus_configured: bool
    consumer_running: bool


# Endpoints
@app.get("/health", response_model=HealthResponse)
async def health():
    """Basic health check."""
    return HealthResponse(
        status="healthy",
        version="1.0.0",
        service="ppt-orchestrator"
    )


@app.get("/health/detailed", response_model=DetailedHealthResponse)
async def detailed_health():
    """Detailed health check with service connectivity."""
    # Check Cosmos DB
    cosmos_ok = False
    try:
        cosmos_service._get_client()
        cosmos_ok = True
    except Exception as e:
        logger.error(f"Cosmos health check failed: {e}")

    # Check if services are configured
    storage_ok = bool(settings.storage_account)
    openai_ok = bool(settings.openai_endpoint)
    servicebus_ok = bool(settings.servicebus_namespace)

    # Check if consumer task is running
    consumer_ok = consumer_task is not None and not consumer_task.done()

    all_ok = all([cosmos_ok, storage_ok, openai_ok, servicebus_ok, consumer_ok])

    return DetailedHealthResponse(
        status="healthy" if all_ok else "degraded",
        version="1.0.0",
        service="ppt-orchestrator",
        cosmos_connected=cosmos_ok,
        storage_connected=storage_ok,
        openai_configured=openai_ok,
        servicebus_configured=servicebus_ok,
        consumer_running=consumer_ok
    )


@app.get("/status/{job_id}")
async def get_job_status(job_id: str):
    """Get the status of a specific job."""
    job = cosmos_service.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    return {
        "jobId": job_id,
        "status": job.get("currentStage", "unknown"),
        "progress": job.get("progress", 0),
        "downloadUrl": job.get("downloadUrl"),
        "qualityScore": job.get("qualityScore"),
        "errorMessage": job.get("errorMessage")
    }


class ManualTriggerRequest(BaseModel):
    job_id: str
    request_id: str = "manual"
    presentation_context: Dict[str, Any]
    data_collections: list = []
    brand_config: Dict[str, Any] = {}


@app.post("/trigger")
async def manual_trigger(request: ManualTriggerRequest):
    """Manually trigger a pipeline run (for testing)."""
    logger.info(f"Manual trigger for job: {request.job_id}")

    # Create job in Cosmos
    cosmos_service.update_job(request.job_id, {
        "currentStage": "queued",
        "progress": 0
    })

    # Run pipeline in background
    asyncio.create_task(
        run_pipeline(
            job_id=request.job_id,
            request_id=request.request_id,
            presentation_context=request.presentation_context,
            data_collections=request.data_collections,
            brand_config=request.brand_config
        )
    )

    return {"status": "triggered", "jobId": request.job_id}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
