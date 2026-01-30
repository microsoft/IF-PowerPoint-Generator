#!/usr/bin/env python3
"""
Local test script for V3 Assistants API workflow.
Run this to debug chart generation and file capture.
"""
import os
import json
import logging
from pathlib import Path

# Setup logging
logging.basicConfig(level=logging.DEBUG, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

# Load environment from .env if exists
from dotenv import load_dotenv
load_dotenv()

def test_assistants_api():
    """Test the Assistants API chart generation."""
    from openai import AzureOpenAI
    from azure.identity import DefaultAzureCredential, get_bearer_token_provider

    # Setup client
    credential = DefaultAzureCredential()
    token_provider = get_bearer_token_provider(
        credential,
        "https://cognitiveservices.azure.com/.default"
    )

    endpoint = os.environ.get("AZURE_OPENAI_ENDPOINT")
    deployment = os.environ.get("AZURE_OPENAI_GPT_DEPLOYMENT", "gpt-4o")

    print(f"Endpoint: {endpoint}")
    print(f"Deployment: {deployment}")

    client = AzureOpenAI(
        azure_endpoint=endpoint,
        azure_ad_token_provider=token_provider,
        api_version="2024-08-01-preview"
    )

    # Load system prompt
    prompt_path = Path(__file__).parent / "src" / "prompts" / "system_prompt.md"
    if prompt_path.exists():
        system_prompt = prompt_path.read_text()
        system_prompt = system_prompt.replace("{primary_color}", "#003366")
        system_prompt = system_prompt.replace("{secondary_color}", "#50E6FF")
    else:
        system_prompt = "You are a presentation generator. Create charts using Plotly."

    # Create or get assistant
    assistant_id = os.environ.get("AZURE_OPENAI_ASSISTANT_ID")

    if assistant_id:
        print(f"Using existing assistant: {assistant_id}")
        assistant = client.beta.assistants.retrieve(assistant_id)
    else:
        print("Creating new assistant...")
        assistant = client.beta.assistants.create(
            name="test-ppt-generator",
            instructions=system_prompt,
            model=deployment,
            tools=[{"type": "code_interpreter"}]
        )
        print(f"Created assistant: {assistant.id}")
        print(f"SET THIS: export AZURE_OPENAI_ASSISTANT_ID={assistant.id}")

    # Sample data (simplified version of sample 18)
    sample_data = [
        {
            "title": "IT Assessment",
            "data": {
                "maturity_scores": {
                    "Strategy & Planning": {"current": 2.4, "target": 4.0},
                    "Service Delivery": {"current": 2.8, "target": 3.5},
                    "Technology Management": {"current": 3.1, "target": 4.0},
                    "Talent & Organization": {"current": 2.2, "target": 3.5}
                },
                "investment_breakdown": {
                    "Run the Business": 68,
                    "Grow the Business": 22,
                    "Transform the Business": 10
                }
            }
        }
    ]

    # Create thread
    thread = client.beta.threads.create()
    print(f"Created thread: {thread.id}")

    # Send message
    user_message = f"""Create a presentation with charts.

DATA:
```json
{json.dumps(sample_data, indent=2)}
```

REQUIREMENTS:
1. Generate 2 charts using Plotly:
   - Bar chart for maturity scores (current vs target)
   - Donut chart for investment breakdown
2. Save each chart as PNG (chart_1.png, chart_2.png)
3. Return JSON with slide definitions

Return ONLY JSON, no markdown."""

    client.beta.threads.messages.create(
        thread_id=thread.id,
        role="user",
        content=user_message
    )

    # Run assistant
    print("Running assistant...")
    run = client.beta.threads.runs.create(
        thread_id=thread.id,
        assistant_id=assistant.id
    )

    # Poll for completion
    import time
    while run.status in ["queued", "in_progress", "requires_action"]:
        time.sleep(2)
        run = client.beta.threads.runs.retrieve(
            thread_id=thread.id,
            run_id=run.id
        )
        print(f"Run status: {run.status}")

    print(f"Final status: {run.status}")

    if run.status != "completed":
        print(f"ERROR: Run failed with status {run.status}")
        if hasattr(run, 'last_error'):
            print(f"Error: {run.last_error}")
        return

    # Get run steps to find files
    print("\n=== RUN STEPS ===")
    run_steps = client.beta.threads.runs.steps.list(
        thread_id=thread.id,
        run_id=run.id
    )

    file_ids = []
    for step in run_steps.data:
        print(f"Step type: {step.type}")

        if step.type == "tool_calls":
            for tool_call in step.step_details.tool_calls:
                print(f"  Tool call type: {tool_call.type}")

                if tool_call.type == "code_interpreter":
                    print(f"  Code input length: {len(tool_call.code_interpreter.input)}")
                    print(f"  Outputs count: {len(tool_call.code_interpreter.outputs)}")

                    for output in tool_call.code_interpreter.outputs:
                        print(f"    Output type: {output.type}")

                        if output.type == "image":
                            file_id = output.image.file_id
                            file_ids.append(file_id)
                            print(f"    IMAGE FILE ID: {file_id}")
                        elif output.type == "logs":
                            print(f"    Logs: {output.logs[:200]}...")

    print(f"\nTotal image files found: {len(file_ids)}")

    # Download files
    print("\n=== DOWNLOADING FILES ===")
    for idx, file_id in enumerate(file_ids):
        try:
            content = client.files.content(file_id)
            file_bytes = content.read()

            # Save locally for inspection
            filename = f"test_chart_{idx+1}.png"
            with open(filename, "wb") as f:
                f.write(file_bytes)

            print(f"Downloaded {file_id} -> {filename} ({len(file_bytes)} bytes)")
        except Exception as e:
            print(f"ERROR downloading {file_id}: {e}")

    # Get messages
    print("\n=== ASSISTANT RESPONSE ===")
    messages = client.beta.threads.messages.list(thread_id=thread.id)

    for msg in messages.data:
        if msg.role == "assistant":
            for content in msg.content:
                if content.type == "text":
                    print(f"Response text (first 500 chars):\n{content.text.value[:500]}")

    # Cleanup
    print("\n=== CLEANUP ===")
    try:
        client.beta.threads.delete(thread_id=thread.id)
        print("Thread deleted")
    except Exception as e:
        print(f"Could not delete thread: {e}")


if __name__ == "__main__":
    test_assistants_api()
