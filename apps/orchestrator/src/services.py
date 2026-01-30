"""
Azure services for the orchestrator.
All connections use managed identity (DefaultAzureCredential).
"""
import os
import logging
from typing import Optional, Dict, Any, List
from datetime import datetime, timedelta
from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient
from azure.servicebus.aio import ServiceBusClient as AsyncServiceBusClient
from azure.cosmos import CosmosClient
from azure.cosmos.aio import CosmosClient as AsyncCosmosClient
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from azure.storage.blob.aio import BlobServiceClient as AsyncBlobServiceClient

logger = logging.getLogger(__name__)


class Settings:
    """Application settings from environment variables."""

    def __init__(self):
        # Service Bus (managed identity)
        self.servicebus_namespace = os.environ.get("SERVICEBUS_NAMESPACE", "")
        self.servicebus_queue = os.environ.get("SERVICEBUS_QUEUE_NAME", "ppt-generation-jobs")

        # Cosmos DB (managed identity)
        self.cosmos_endpoint = os.environ.get("COSMOS_ENDPOINT", "")
        self.cosmos_database = os.environ.get("COSMOS_DATABASE", "ppt-generator")

        # Blob Storage (managed identity)
        self.storage_account = os.environ.get("STORAGE_ACCOUNT_NAME", "")
        self.templates_container = os.environ.get("TEMPLATES_CONTAINER", "ppt-templates")
        self.outputs_container = os.environ.get("OUTPUT_CONTAINER", "ppt-outputs")

        # Azure OpenAI (uses managed identity, no API key needed)
        self.openai_endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT", "")
        self.openai_gpt_deployment = os.environ.get("AZURE_OPENAI_GPT_DEPLOYMENT", "gpt-4o")
        self.openai_mini_deployment = os.environ.get("AZURE_OPENAI_MINI_DEPLOYMENT", "gpt-4o-mini")

        # Application Insights
        self.appinsights_connection_string = os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING", "")


settings = Settings()

# Log settings on import (without secrets)
logger.info(f"Settings loaded:")
logger.info(f"  SERVICEBUS_NAMESPACE: {settings.servicebus_namespace or '(not set)'}")
logger.info(f"  SERVICEBUS_QUEUE_NAME: {settings.servicebus_queue}")
logger.info(f"  COSMOS_ENDPOINT: {settings.cosmos_endpoint or '(not set)'}")
logger.info(f"  COSMOS_DATABASE: {settings.cosmos_database}")
logger.info(f"  STORAGE_ACCOUNT_NAME: {settings.storage_account or '(not set)'}")
logger.info(f"  AZURE_OPENAI_ENDPOINT: {settings.openai_endpoint or '(not set)'}")
logger.info(f"  Authentication: Managed Identity (DefaultAzureCredential)")


class CosmosService:
    """Cosmos DB service using managed identity."""

    def __init__(self):
        self._client = None
        self._credential = DefaultAzureCredential()

    def _get_client(self):
        if self._client is None:
            self._client = CosmosClient(
                settings.cosmos_endpoint,
                credential=self._credential
            )
        return self._client

    def _get_container(self, container_name: str = "jobs"):
        client = self._get_client()
        database = client.get_database_client(settings.cosmos_database)
        return database.get_container_client(container_name)

    def get_job(self, job_id: str) -> Optional[Dict[str, Any]]:
        """Get a job by ID."""
        container = self._get_container()
        try:
            query = "SELECT * FROM c WHERE c.id = @job_id"
            items = list(container.query_items(
                query=query,
                parameters=[{"name": "@job_id", "value": job_id}],
                enable_cross_partition_query=True
            ))
            return items[0] if items else None
        except Exception as e:
            logger.error(f"Error getting job {job_id}: {e}")
            return None

    def update_job(self, job_id: str, updates: Dict[str, Any]) -> bool:
        """Update a job with new values."""
        logger.info(f"Updating job {job_id} with: {updates}")
        container = self._get_container()
        try:
            job = self.get_job(job_id)
            if not job:
                logger.warning(f"Job {job_id} not found for update")
                return False

            job.update(updates)
            job["updatedAt"] = datetime.utcnow().isoformat()
            container.upsert_item(job)
            logger.info(f"Job {job_id} updated successfully")
            return True
        except Exception as e:
            logger.exception(f"Error updating job {job_id}: {e}")
            return False

    def log_error(self, job_id: str, error_type: str, error_message: str,
                  node_name: str = None, raw_data: Dict = None):
        """Log an error to the errors container."""
        container = self._get_container("errors")
        try:
            error_doc = {
                "id": f"{job_id}-{datetime.utcnow().timestamp()}",
                "jobId": job_id,
                "errorType": error_type,
                "errorMessage": error_message,
                "nodeName": node_name,
                "rawData": raw_data,
                "timestamp": datetime.utcnow().isoformat()
            }
            container.create_item(error_doc)
        except Exception as e:
            logger.error(f"Error logging error for job {job_id}: {e}")

    def list_templates(self) -> List[Dict[str, Any]]:
        """List all templates from Cosmos DB."""
        container = self._get_container("templates")
        try:
            query = "SELECT * FROM c"
            items = list(container.query_items(
                query=query,
                enable_cross_partition_query=True
            ))
            logger.info(f"Loaded {len(items)} templates from Cosmos DB")
            return items
        except Exception as e:
            logger.exception(f"Error listing templates: {e}")
            return []


class BlobStorageService:
    """Blob Storage service using managed identity."""

    def __init__(self):
        self._client = None
        self._credential = DefaultAzureCredential()

    def _get_client(self) -> BlobServiceClient:
        if self._client is None:
            account_url = f"https://{settings.storage_account}.blob.core.windows.net"
            self._client = BlobServiceClient(account_url, credential=self._credential)
        return self._client

    def download_template(self, template_id: str) -> bytes:
        """Download a template file."""
        client = self._get_client()
        container = client.get_container_client(settings.templates_container)

        # Try template_id/template.pptx first, then template_id.pptx
        for path in [f"{template_id}/template.pptx", f"{template_id}.pptx"]:
            try:
                blob = container.get_blob_client(path)
                return blob.download_blob().readall()
            except Exception:
                continue

        raise FileNotFoundError(f"Template {template_id} not found")

    def get_template_metadata(self, template_id: str) -> Optional[Dict[str, Any]]:
        """
        Download and parse template metadata.json for dynamic layout selection.

        Args:
            template_id: Template identifier

        Returns:
            Parsed metadata dict with layoutSelectionGuide, or None if not found
        """
        import json
        client = self._get_client()
        container = client.get_container_client(settings.templates_container)

        try:
            blob = container.get_blob_client(f"{template_id}/metadata.json")
            metadata_bytes = blob.download_blob().readall()
            return json.loads(metadata_bytes)
        except Exception as e:
            logger.warning(f"Could not load metadata for template {template_id}: {e}")
            return None

    def upload_output(self, job_id: str, content: bytes, filename: str = "presentation.pptx") -> str:
        """Upload generated presentation."""
        client = self._get_client()
        container = client.get_container_client(settings.outputs_container)
        blob_path = f"{job_id}/{filename}"
        blob = container.get_blob_client(blob_path)
        blob.upload_blob(content, overwrite=True)
        return blob_path

    def upload_chart_image(self, job_id: str, chart_id: str, image_bytes: bytes) -> str:
        """Upload a chart image."""
        client = self._get_client()
        container = client.get_container_client(settings.outputs_container)
        blob_path = f"{job_id}/charts/{chart_id}.png"
        blob = container.get_blob_client(blob_path)
        blob.upload_blob(image_bytes, overwrite=True)
        return blob_path

    def generate_sas_url(self, job_id: str, filename: str = "presentation.pptx",
                         expiry_hours: int = 24) -> str:
        """Generate a SAS URL for download."""
        client = self._get_client()
        blob_path = f"{job_id}/{filename}"

        # Get user delegation key for managed identity
        start_time = datetime.utcnow()
        expiry_time = start_time + timedelta(hours=expiry_hours)

        user_delegation_key = client.get_user_delegation_key(
            key_start_time=start_time,
            key_expiry_time=expiry_time
        )

        sas_token = generate_blob_sas(
            account_name=settings.storage_account,
            container_name=settings.outputs_container,
            blob_name=blob_path,
            user_delegation_key=user_delegation_key,
            permission=BlobSasPermissions(read=True),
            expiry=expiry_time,
            start=start_time
        )

        return f"https://{settings.storage_account}.blob.core.windows.net/{settings.outputs_container}/{blob_path}?{sas_token}"


class ServiceBusConsumer:
    """Service Bus consumer using managed identity."""

    def __init__(self):
        self._credential = DefaultAzureCredential()

    def get_client(self) -> ServiceBusClient:
        """Get a synchronous Service Bus client."""
        return ServiceBusClient(
            fully_qualified_namespace=settings.servicebus_namespace,
            credential=self._credential
        )

    async def get_async_client(self) -> AsyncServiceBusClient:
        """Get an async Service Bus client."""
        return AsyncServiceBusClient(
            fully_qualified_namespace=settings.servicebus_namespace,
            credential=self._credential
        )


class OpenAIService:
    """Azure OpenAI service using managed identity."""

    def __init__(self):
        self._client = None
        self._credential = DefaultAzureCredential()

    def _get_client(self):
        if self._client is None:
            from openai import AzureOpenAI
            from azure.identity import get_bearer_token_provider

            # Get token provider for Azure OpenAI using managed identity
            token_provider = get_bearer_token_provider(
                self._credential,
                "https://cognitiveservices.azure.com/.default"
            )

            self._client = AzureOpenAI(
                azure_endpoint=settings.openai_endpoint,
                azure_ad_token_provider=token_provider,
                api_version="2024-08-01-preview"
            )
            logger.info("Azure OpenAI client initialized with managed identity")
        return self._client

    def chat_completion(self, messages: List[Dict], model: str = None,
                        response_format=None, temperature: float = 0.7) -> Any:
        """Get a chat completion."""
        client = self._get_client()
        deployment = model or settings.openai_gpt_deployment

        kwargs = {
            "model": deployment,
            "messages": messages,
            "temperature": temperature
        }

        if response_format:
            return client.beta.chat.completions.parse(**kwargs, response_format=response_format)
        else:
            return client.chat.completions.create(**kwargs)

    def chat_completion_mini(self, messages: List[Dict], response_format=None,
                             temperature: float = 0.7) -> Any:
        """Get a chat completion using GPT-4o-mini (for content generation)."""
        return self.chat_completion(
            messages=messages,
            model=settings.openai_mini_deployment,
            response_format=response_format,
            temperature=temperature
        )


class AssistantsService:
    """
    Azure OpenAI Assistants API service for v3 architecture.

    Returns chart blueprints (JSON specifications) that the orchestrator
    renders locally using Plotly + kaleido. No Code Interpreter needed.
    """

    def __init__(self):
        self._client = None
        self._credential = DefaultAzureCredential()
        self._assistant_id = os.environ.get("AZURE_OPENAI_ASSISTANT_ID")

    def _get_client(self):
        if self._client is None:
            from openai import AzureOpenAI
            from azure.identity import get_bearer_token_provider

            token_provider = get_bearer_token_provider(
                self._credential,
                "https://cognitiveservices.azure.com/.default"
            )

            self._client = AzureOpenAI(
                azure_endpoint=settings.openai_endpoint,
                azure_ad_token_provider=token_provider,
                api_version="2024-08-01-preview"
            )
            logger.info("Azure OpenAI Assistants client initialized")
        return self._client

    def get_or_create_assistant(self, system_prompt: str) -> str:
        """Get existing assistant or create a new one."""
        client = self._get_client()

        # If we have an assistant ID, verify it exists
        if self._assistant_id:
            try:
                assistant = client.beta.assistants.retrieve(self._assistant_id)
                logger.info(f"Using existing assistant: {assistant.id}")
                return assistant.id
            except Exception as e:
                logger.warning(f"Could not retrieve assistant {self._assistant_id}: {e}")

        # Create new assistant (no tools needed - returns JSON blueprints)
        assistant = client.beta.assistants.create(
            name="presentation-generator",
            instructions=system_prompt,
            model=settings.openai_gpt_deployment
        )
        logger.info(f"Created new assistant: {assistant.id}")
        self._assistant_id = assistant.id
        return assistant.id

    def generate_presentation(
        self,
        assistant_id: str,
        title: str,
        audience: str,
        data_collections: list,
        brand_config: dict
    ) -> tuple:
        """
        Generate a presentation using the Assistants API.

        The assistant returns JSON with chart blueprints that describe how to
        render charts. The orchestrator renders these locally using Plotly.

        Returns:
            tuple: (response_json: dict, blueprints: list[ChartBlueprint])
        """
        import json
        import time
        from .models.v3 import ChartBlueprint

        client = self._get_client()

        # Build the user message
        primary_color = brand_config.get("primaryColor", brand_config.get("primary_color", "#003366"))
        secondary_color = brand_config.get("secondaryColor", brand_config.get("secondary_color", "#50E6FF"))

        user_message = f"""Create an executive-quality presentation.

PRESENTATION DETAILS:
- Title: {title}
- Audience: {audience}
- Brand Primary Color: {primary_color}
- Brand Secondary Color: {secondary_color}

DATA TO ANALYZE AND VISUALIZE:
```json
{json.dumps(data_collections, indent=2, default=str)}
```

REQUIREMENTS:
1. Analyze all data collections thoroughly
2. Design a compelling narrative arc
3. For each chart, provide a chart_blueprint JSON object (NOT Python code)
4. The chart_file should reference the chart_id with .png extension (e.g., "chart_1.png")
5. Return a JSON response with the presentation structure
6. Every data element should have its own slide with appropriate visualization

CRITICAL: Return ONLY the JSON response, no markdown formatting or explanation.
Each data slide must include a chart_blueprint object that describes the chart to render."""

        # Create thread
        thread = client.beta.threads.create()
        logger.info(f"Created thread: {thread.id}")

        # Add message
        client.beta.threads.messages.create(
            thread_id=thread.id,
            role="user",
            content=user_message
        )

        # Run assistant
        run = client.beta.threads.runs.create(
            thread_id=thread.id,
            assistant_id=assistant_id
        )
        logger.info(f"Created run: {run.id}")

        # Poll for completion
        max_wait = 300  # 5 minutes
        start_time = time.time()

        while run.status in ["queued", "in_progress", "requires_action"]:
            if time.time() - start_time > max_wait:
                raise TimeoutError(f"Assistant run timed out after {max_wait}s")

            time.sleep(2)
            run = client.beta.threads.runs.retrieve(
                thread_id=thread.id,
                run_id=run.id
            )
            logger.info(f"Run status: {run.status}")

        if run.status != "completed":
            raise RuntimeError(f"Assistant run failed with status: {run.status}")

        # Get messages
        messages = client.beta.threads.messages.list(thread_id=thread.id)

        # Find the assistant's response
        response_text = None

        for message in messages.data:
            if message.role == "assistant":
                for content in message.content:
                    if content.type == "text":
                        response_text = content.text.value
                        break
                if response_text:
                    break

        if not response_text:
            raise RuntimeError("No response text from assistant")

        # Parse JSON from response (handle markdown code blocks)
        response_text = response_text.strip()
        if response_text.startswith("```"):
            # Extract JSON from code block
            lines = response_text.split("\n")
            json_lines = []
            in_block = False
            for line in lines:
                if line.startswith("```") and not in_block:
                    in_block = True
                    continue
                elif line.startswith("```") and in_block:
                    break
                elif in_block:
                    json_lines.append(line)
            response_text = "\n".join(json_lines)

        response_json = json.loads(response_text)

        # Extract chart blueprints from slides
        blueprints = []
        if "slides" in response_json:
            for slide in response_json["slides"]:
                blueprint_data = slide.get("chart_blueprint")
                if blueprint_data:
                    try:
                        blueprint = ChartBlueprint(**blueprint_data)
                        blueprints.append(blueprint)
                        logger.info(f"Extracted blueprint: {blueprint.chart_id} ({blueprint.chart_type})")
                    except Exception as e:
                        logger.error(f"Failed to parse blueprint for slide {slide.get('slide_number')}: {e}")

        logger.info(f"Total blueprints extracted: {len(blueprints)}")

        # Clean up thread
        try:
            client.beta.threads.delete(thread_id=thread.id)
        except Exception as e:
            logger.warning(f"Could not delete thread: {e}")

        return response_json, blueprints


# Singleton instances
cosmos_service = CosmosService()
blob_service = BlobStorageService()
servicebus_consumer = ServiceBusConsumer()
openai_service = OpenAIService()
assistants_service = AssistantsService()
