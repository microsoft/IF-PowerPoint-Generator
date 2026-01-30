# Specifications: PPT Generator Service

## Overview

The PPT Generator Service is an AI-powered presentation generation system that transforms structured data collections into professional PowerPoint presentations. Built on Azure with a LangGraph-orchestrated AI pipeline, the service processes complex data through 9 specialized nodes to produce contextually-aware, visually-optimized presentations.

**Project Name:** pptgen
**Purpose:** AI-driven presentation generation from structured data
**Technology Stack:** Azure PaaS, Python 3.11, LangGraph, GPT-4o
**Deployment Model:** 6-stage microservices architecture

---

## Functional Specifications

### Feature 1: Async Presentation Generation API

**Description:**
RESTful API layer that accepts structured data payloads, queues generation jobs, and provides status tracking with downloadable outputs.

**Acceptance Criteria:**
- [x] HTTP POST endpoint accepts JSON payloads with data collections
- [x] Job queued to Service Bus within 500ms
- [x] Status endpoint returns real-time job progress
- [x] Completed presentations available via SAS URL
- [x] Cache hit returns result in < 2 seconds
- [x] Supports concurrent job submissions

**Technical Details:**
- Azure Services: Azure Functions (Python 3.11, Elastic Premium EP1)
- Authentication: Managed Identity for all service-to-service calls
- Data Flow: Client → Functions → Service Bus → Status tracking in Cosmos DB
- Caching: Content hash-based with 24-hour TTL in Cosmos DB

**Endpoints:**
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/presentations/generate` | POST | Submit generation job |
| `/api/presentations/status/{job_id}` | GET | Query job status |
| `/api/templates` | GET | List available templates |
| `/api/templates/{template_id}` | GET | Get template metadata |
| `/api/health` | GET | Health check |

---

### Feature 2: LangGraph AI Pipeline (9-Node Orchestration)

**Description:**
Multi-stage AI workflow that analyzes data, designs narrative structure, selects optimal visualizations, generates content, and validates output quality.

**Acceptance Criteria:**
- [x] All 9 nodes execute in sequence with state persistence
- [x] Each node has defined inputs, outputs, and error handling
- [x] Retry logic implemented for visualization and content generation
- [x] Quality validation prevents low-quality outputs
- [x] Token usage tracked per node
- [x] Processing telemetry logged to SQL

**Technical Details:**
- Azure Services: Container Apps (1-100 replicas), Azure OpenAI (GPT-4o, GPT-4o-mini)
- Authentication: Managed Identity
- Data Flow: Service Bus message → LangGraph state machine → Blob storage output
- Monitoring: Application Insights with per-node instrumentation

**Pipeline Nodes:**

| Node | Name | AI Model | Purpose |
|------|------|----------|---------|
| 1 | Context Interpreter | GPT-4o | Understand audience, goals, tone |
| 2 | Data Classifier | GPT-4o | Analyze data patterns and types |
| 3 | Narrative Architect | GPT-4o | Design story arc and slide sequence |
| 4 | Template Selector | Rule-based | Match best template for content |
| 5 | Visualization Strategist | GPT-4o | AI-driven chart selection |
| 5b | Visualization Validator | Rule-based | Ensure no empty slides |
| 6 | Content Generator | GPT-4o-mini | Create slide text and bullets |
| 7 | Slide Builder | python-pptx | Assemble PPTX with charts |
| 8 | Quality Validator | Rule-based | Verify output quality |

**State Management:**
- Intermediate results stored in Cosmos DB
- State serialization for retry/resume capability
- Progress updates every 10 seconds

---

### Feature 3: AI-Driven Visualization Selection

**Description:**
Intelligent chart type selection based on data patterns, using prescriptive mapping embedded in LLM prompts with guaranteed fallback logic.

**Acceptance Criteria:**
- [x] LLM analyzes data structure and selects optimal chart type
- [x] Prescriptive mapping table guides AI decisions
- [x] Visualization Validator ensures every slide has content
- [x] Fallback logic applies rule-based defaults if AI fails
- [x] No presentation generated with empty slides
- [x] Supports 11 visualization types

**Technical Details:**
- Azure Services: Azure OpenAI (GPT-4o), Plotly + Kaleido for rendering
- Authentication: Managed Identity
- Data Flow: Data collection → AI analysis → Plotly config → PNG export → PPTX embedding

**Supported Visualizations:**

| Visualization Type | Best For | Data Types |
|--------------------|----------|------------|
| LINE | Trends over time | TIME_SERIES |
| BAR | Category comparisons | CATEGORICAL, COMPARISON, RANKING |
| GROUPED_BAR | Multi-series comparisons | COMPARISON, CATEGORICAL |
| HORIZONTAL_BAR | Long labels, rankings | RANKING, CATEGORICAL |
| PIE | Part-to-whole (≤6 slices) | PERCENTAGE |
| DONUT | Part-to-whole with center metric | PERCENTAGE |
| FUNNEL | Sequential stages | FUNNEL |
| SANKEY | Flow between entities | FLOW |
| RADAR | Multi-dimensional comparisons | VENDOR_SCORING, COMPARISON |
| DIVERGING_BAR | Gap analysis (current vs. target) | SKILLS_GAP, COMPARISON |
| TEXT_BLOCK | Narrative content | FREE_FORM_TEXT |
| TABLE | Detailed data, many metrics | ANY (fallback) |

**Guaranteed Output Logic:**
1. AI attempts chart selection
2. If AI output incomplete → Apply prescriptive mapping based on data_type
3. If data_type unknown → Infer from data structure
4. If inference fails → Default to TABLE
5. Validator verifies every collection has a visualization

---

### Feature 4: FREE_FORM_TEXT Multi-Slide Generation

**Description:**
Automatic detection and processing of long-form narrative content with intelligent splitting across multiple slides.

**Acceptance Criteria:**
- [x] Detects narrative content via heuristics (length, structure, keywords)
- [x] Automatically splits content based on character count
- [x] Preserves paragraph boundaries and bullet lists
- [x] Extracts priority bullets (action items, quantified statements, key concepts)
- [x] Generates section headers for multi-section content
- [x] Supports 4 layout options (text_full, text_with_callout, text_two_column, section_header)

**Technical Details:**
- Azure Services: Azure OpenAI (GPT-4o-mini for content extraction)
- Authentication: Managed Identity
- Data Flow: Text input → Detection → Segmentation → Bullet extraction → Layout selection

**Detection Criteria:**

1. **Key Name Patterns:**
   - `text`, `narrative`, `recommendations`, `analysis`, `summary`
   - `description`, `overview`, `findings`, `insights`, `commentary`
   - `executive_summary`, `key_findings`, `next_steps`

2. **Content Length:**
   - Single string > 500 characters
   - Combined strings > 1000 characters

3. **Content Patterns:**
   - Numbered lists (e.g., "1.", "2.", "3.")
   - Bullet points (e.g., "- ", "• ", "* ")
   - Section headers (e.g., "### ", "## ", lines ending with ":")
   - Multi-paragraph structure (multiple `\n\n` separators)

**Multi-Slide Logic:**

| Content Length | Slides Generated | Strategy |
|----------------|------------------|----------|
| < 500 chars | 1 slide | Single `text_full` layout |
| 500-1500 chars | 2 slides | Split at paragraph break |
| 1500-3000 chars | 2-3 slides | Split by sections or logical breaks |
| > 3000 chars | 3+ slides | Section dividers + content slides |

**Bullet Extraction Priority:**
- 30% Action Items (verbs: Implement, Develop, Create, Review)
- 30% Quantified Statements (numbers, percentages, metrics)
- 40% Key Concepts (proper nouns, technical terms, topic sentences)

---

### Feature 5: Template Metadata System with Auto-Introspection

**Description:**
Automatic template analysis and metadata generation that enables dynamic layout selection without hardcoded indices.

**Acceptance Criteria:**
- [x] Templates uploaded to blob storage trigger automatic introspection
- [x] Metadata extracted includes layouts, placeholders, dimensions
- [x] Layout Selection Guide maps content types to indices
- [x] Content layouts filtered to exclude boilerplate slides
- [x] Metadata cached in Cosmos DB for fast retrieval
- [x] Orchestrator uses metadata for dynamic slide assembly

**Technical Details:**
- Azure Services: Azure Functions (Timer Trigger), Blob Storage, Cosmos DB
- Authentication: Managed Identity
- Data Flow: Template upload → Timer detection (1 min) → Introspection → metadata.json generation → Cosmos cache

**Metadata Schema:**

```json
{
  "templateId": "template-name",
  "layouts": [
    {
      "index": 0,
      "name": "Title Slide",
      "category": "title_slide",
      "placeholders": [...]
    }
  ],
  "layoutSelectionGuide": {
    "title_slide": [0],
    "section_header": [2],
    "bulleted_text": [1],
    "chart_or_graph": [3],
    "text_with_graphic": [4],
    "paragraph_text": [5]
  },
  "contentLayouts": [0, 1, 2, 3, 4, 5],
  "supportedContentTypes": ["TIME_SERIES", "CATEGORICAL", ...]
}
```

**Template Introspection Service:**
- Analyzes PPTX using python-pptx
- Extracts slide master layouts
- Maps placeholders by type and position
- Generates layout selection guide
- Filters boilerplate slides ("End Slide", "Thank You")

---

### Feature 6: Telemetry and Monitoring

**Description:**
Comprehensive telemetry tracking for job metrics, node performance, template usage, and error logging.

**Acceptance Criteria:**
- [x] All requests logged to SQL (JobRequests table)
- [x] Per-node metrics captured (ProcessingMetrics table)
- [x] Data collection stats tracked (DataCollectionStats table)
- [x] Template usage patterns logged (TemplateUsage table)
- [x] Errors logged with context (ErrorLog table)
- [x] Application Insights integration for distributed tracing

**Technical Details:**
- Azure Services: Azure SQL (Basic SKU), Application Insights, Log Analytics
- Authentication: Entra ID (Managed Identity)
- Data Flow: Orchestrator → SQL writes via managed identity

**SQL Schema:**

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| JobRequests | Request metadata | JobId, RequestId, Status, TemplateUsed, DurationMs, SlideCount |
| ProcessingMetrics | Per-node performance | JobId, NodeName, DurationMs, TokensUsed, Success |
| DataCollectionStats | Data source analysis | JobId, CollectionId, InferredDataType, VisualizationType |
| TemplateUsage | Template selection tracking | JobId, TemplateId, WasAISelected, WasFallback |
| ErrorLog | Error tracking | JobId, ErrorCode, ErrorMessage, NodeName |

---

## Non-Functional Specifications

### Performance

| Metric | Target | Measurement |
|--------|--------|-------------|
| Job submission latency | < 500ms | P95 response time |
| Cache hit response | < 2 seconds | End-to-end |
| Pipeline processing (5 slides) | < 60 seconds | Total duration |
| Pipeline processing (20 slides) | < 3 minutes | Total duration |
| Concurrent jobs | 100+ | Service Bus queue depth |
| Orchestrator scaling | 1-100 replicas | KEDA autoscale on queue depth (25 msgs) |

### Security

**Authentication:** Managed Identity only - no connection strings or access keys

**Authorization:** Azure RBAC for all resources

**Encryption:**
- At rest: Microsoft-managed keys for all services
- In transit: TLS 1.2+ enforced on all endpoints

**Network:**
- Public endpoints (POC configuration)
- Production recommendation: Private endpoints + VNet integration

**SQL Database:**
- Entra-only authentication (no SQL username/password)
- Managed identities granted db_datareader, db_datawriter roles

**Storage Account:**
- Shared key access disabled
- Public network access enabled (required for MI)
- Blob access via RBAC only

**Service Bus:**
- Premium tier (required for managed identity)
- Azure Service Bus Data Sender/Receiver roles

**Azure OpenAI:**
- Cognitive Services OpenAI User role
- Content filtering enabled (Medium severity thresholds)

### Scalability

**Container Apps:**
- Min replicas: 1 (always-on for Service Bus consumption)
- Max replicas: 100 (KEDA autoscale)
- Trigger: Queue depth > 25 messages
- CPU: 1.0 vCPU per replica
- Memory: 2.0 GB per replica

**Azure Functions:**
- Elastic Premium EP1 plan
- Auto-scale: 1-20 workers
- Pre-warmed instances: 1

**Cosmos DB:**
- Serverless (POC)
- Production recommendation: Provisioned throughput with autoscale

**Service Bus:**
- Premium 1 MU (1000 msgs/sec throughput)
- Upgradeable to 4 MU

### Monitoring

**Application Insights:**
- Workspace-based telemetry
- Adaptive sampling enabled
- Daily cap: 100 GB
- Retention: 30 days

**Log Analytics:**
- Centralized log storage
- 30-day retention
- Diagnostic settings on all services

**Key Metrics:**
- Job completion rate
- Average processing time per node
- Token usage per deployment
- Error rate by node
- Queue depth trends

### Reliability

**Retry Logic:**
- Service Bus: 3 delivery attempts with exponential backoff
- Workflow: Visualization retry (Node 5 → Node 5b)
- Workflow: Content retry (Node 6 → Node 8)

**Dead-Letter Queue:**
- Failed messages after 3 retries
- TTL: 7 days
- Manual reprocessing capability

**State Persistence:**
- Job state in Cosmos DB (7-day TTL)
- Cache in Cosmos DB (24-hour TTL)
- Errors in Cosmos DB (30-day TTL)

---

## Integration Specifications

| System | Direction | Protocol | Authentication |
|--------|-----------|----------|----------------|
| Chat Applications (Internal Apps) | Inbound | HTTP/REST | API key (future) |
| Web Test Portal | Inbound | HTTP/REST | None (test only) |
| Azure Service Bus | Bidirectional | AMQP | Managed Identity |
| Azure Cosmos DB | Outbound | HTTPS | Managed Identity |
| Azure Blob Storage | Outbound | HTTPS | Managed Identity |
| Azure SQL | Outbound | TDS | Entra ID (Managed Identity) |
| Azure OpenAI | Outbound | HTTPS | Managed Identity |

---

## Data Specifications

### Data Models

**Job Message (Service Bus):**
```json
{
  "jobId": "uuid",
  "requestId": "uuid",
  "requestorAppId": "uuid",
  "requestorUserId": "uuid",
  "requestorTenantId": "uuid",
  "title": "Presentation Title",
  "templatePreference": "template-id",
  "dataCollections": [
    {
      "collectionId": "uuid",
      "title": "Collection Title",
      "dataType": "TIME_SERIES",
      "data": { ... }
    }
  ],
  "audience": "Executive",
  "tone": "Professional",
  "webhookUrl": "https://callback-url"
}
```

**Job State (Cosmos DB - jobs container):**
```json
{
  "id": "uuid",
  "jobId": "uuid",
  "requestId": "uuid",
  "status": "queued|processing|completed|failed",
  "progress": 45,
  "currentStage": "Node 5: Visualization Strategist",
  "processingStartedAt": "2025-01-13T10:00:00Z",
  "completedAt": "2025-01-13T10:02:30Z",
  "downloadUrl": "https://blob-url-with-sas",
  "metadata": { ... },
  "warnings": [],
  "errors": [],
  "ttl": 604800
}
```

**Template Metadata (Cosmos DB - templates container):**
```json
{
  "id": "template-id",
  "templateId": "template-id",
  "name": "Template Name",
  "layoutSelectionGuide": { ... },
  "contentLayouts": [0, 1, 2, 3],
  "supportedContentTypes": ["TIME_SERIES", "CATEGORICAL"]
}
```

**Cache Entry (Cosmos DB - cache container):**
```json
{
  "id": "content-hash",
  "contentHash": "sha256-hash",
  "outputUrl": "https://blob-url-with-sas",
  "templateUsed": "template-id",
  "slideCount": 15,
  "cachedAt": "2025-01-13T10:00:00Z",
  "ttl": 86400
}
```

### Data Flows

**Primary Flow (Cache Miss):**
1. Client → Functions API (`POST /api/presentations/generate`)
2. Functions → Cosmos DB (create job record, status: queued)
3. Functions → Service Bus (queue job message)
4. Functions → Client (return 202 Accepted with jobId)
5. Service Bus → Orchestrator (deliver message)
6. Orchestrator → Cosmos DB (update status: processing)
7. Orchestrator → Azure OpenAI (9-node pipeline processing)
8. Orchestrator → Blob Storage (fetch template, upload charts, upload PPTX)
9. Orchestrator → SQL (log telemetry)
10. Orchestrator → Cosmos DB (update status: completed, save manifest, create cache entry)
11. Orchestrator → Client (webhook callback)
12. Client → Functions API (`GET /api/presentations/status/{jobId}`)
13. Functions → Cosmos DB (read job state)
14. Functions → Client (return status + download URL)
15. Client → Blob Storage (download PPTX via SAS URL)

**Cache Hit Flow:**
1. Client → Functions API (`POST /api/presentations/generate`)
2. Functions → Cosmos DB (check cache by content hash)
3. Functions → Client (return 200 OK with cached download URL)

**Template Upload Flow:**
1. User → Blob Storage (upload template.pptx)
2. Timer Trigger → Functions (poll every 1 minute)
3. Functions → Blob Storage (detect new template)
4. Functions → Template Introspection Service (analyze PPTX)
5. Functions → Blob Storage (upload metadata.json)
6. Functions → Cosmos DB (cache metadata in templates container)

---

## Supported Data Types

| Data Type | Description | Example Use Cases |
|-----------|-------------|-------------------|
| TIME_SERIES | Temporal trends with date/time | Revenue over quarters, usage growth |
| CATEGORICAL | Named categories with values | Department budgets, product sales |
| COMPARISON | Side-by-side comparisons | Current vs. target, before/after |
| PERCENTAGE | Part-to-whole relationships | Market share, budget allocation |
| RANKING | Ordered lists by value | Top 10 customers, priority rankings |
| FUNNEL | Sequential stage progression | Sales pipeline, conversion funnels |
| FLOW | Inter-entity flows | Budget allocations, traffic sources |
| DISTRIBUTION | Statistical distributions | Percentile ranges, risk distributions |
| SKILLS_GAP | Current vs. needed analysis | Skill assessments, capability gaps |
| VENDOR_SCORING | Multi-criteria evaluations | Vendor comparisons, SWOT analysis |
| FREE_FORM_TEXT | Long narrative content | Executive summaries, recommendations |

---

## Configuration Management

**Central Configuration File:** `concept/AZURE_CONFIG.json`

**Owner:** cloud-architect

**Purpose:** Centralized tracking of all deployed resources, managed identities, and configuration values

**Auto-Updated By:** Deployment scripts (`deploy.sh`, `deploy-tf.sh`)

**Referenced By:** All deployment scripts, documentation, manual configuration steps

---

## Constraints

**Time:** Maximum 10-day Innovation Factory engagement
**Environment:** Microsoft internal Azure environment
**Authentication:** Managed Identity only - no connection strings
**Network:** Public endpoints (POC) - private endpoints recommended for production
**Scope:** Functional prototype - not production-ready
**Template Requirements:** PowerPoint files must use standard slide layouts and placeholders

---

## Success Criteria

- [x] Prototype demonstrates end-to-end AI-powered presentation generation
- [x] All services authenticate via Managed Identity
- [x] Pipeline processes 11 data types with appropriate visualizations
- [x] FREE_FORM_TEXT generates multi-slide outputs
- [x] Template metadata enables dynamic layout selection
- [x] Telemetry captured for job analysis
- [x] Deployment documented and reproducible
- [x] Code organized for future extension
