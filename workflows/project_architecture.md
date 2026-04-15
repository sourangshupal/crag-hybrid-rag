# Project Architecture

Complete architectural overview of the Corrective RAG with Hybrid Search system.

## System Architecture Overview

```mermaid
flowchart TB
    subgraph Client["Client Layer"]
        User[User/API Client]
        Swagger[Swagger UI<br/>localhost:8000/docs]
    end

    subgraph API["FastAPI Application Layer"]
        Main[main.py<br/>FastAPI App]
        UploadAPI[Upload API<br/>/upload/]
        QueryAPI[Query API<br/>/query/]
        CompareAPI[Compare API<br/>/query/compare]
    end

    subgraph Services["Service Layer"]
        DocProc[DocumentProcessor<br/>Docling Integration]
        Retrieval[RetrievalService<br/>Vector Search]
        CRAG[CRAGService<br/>Relevance + Web]
        LLM[LLMService<br/>OpenAI Wrapper]
        WebSearch[WebSearchService<br/>Tavily Client]
        Rerank[RerankingService<br/>Local/Voyage]
        VectorStore[VectorStore<br/>Qdrant Client]
    end

    subgraph External["External Services"]
        OpenAI[OpenAI API<br/>LLM + Embeddings]
        Qdrant[Qdrant Vector DB<br/>localhost:6333]
        Tavily[Tavily Search API<br/>Web Search]
        Voyage[Voyage AI API<br/>Reranking]
    end

    subgraph Storage["Local Storage"]
        Uploads[uploads/<br/>PDF, MD, TXT, JSON]
    end

    User --> Main
    Swagger --> Main
    Main --> UploadAPI
    Main --> QueryAPI
    Main --> CompareAPI

    UploadAPI --> DocProc
    QueryAPI --> Retrieval
    QueryAPI --> CRAG
    CompareAPI --> QueryAPI

    DocProc --> VectorStore
    Retrieval --> VectorStore
    CRAG --> LLM
    CRAG --> WebSearch
    Rerank --> Retrieval

    VectorStore --> Qdrant
    LLM --> OpenAI
    WebSearch --> Tavily
    Rerank -.->|if voyage| Voyage
    DocProc --> Uploads

    VectorStore --> OpenAI

    style Client fill:#e1f5e1
    style API fill:#fff4e6
    style Services fill:#e6f3ff
    style External fill:#ffe6e6
    style Storage fill:#f0f0f0
```



## Service Layer Architecture

```mermaid
classDiagram
    class RetrievalService {
        +vector_store: VectorStore
        +embedding_service: EmbeddingService
        +retrieve(query, top_k)
    }

    class CRAGService {
        +llm: LLMService
        +web_search: WebSearchService
        +evaluate_relevance(query, chunks)
        +execute_crag(query, chunks)
        +generate_answer_with_crag(query, result)
        +get_augmented_chunks(result)
    }

    class LLMService {
        +client: OpenAI
        +generate(prompt, system_prompt, max_tokens)
        +generate_with_json(prompt, system_prompt)
    }

    class VectorStore {
        +client: QdrantClient
        +search(query_vector, top_k, filter)
        +upsert_chunks(chunks, embeddings, metadata)
        +delete_by_source(source_file)
        -_ensure_collection()
    }

    class DocumentProcessor {
        +converter: DocumentConverter
        +chunker: HybridChunker
        +process_document(file_path, file_type)
        -_create_metadata(chunk, index, source, content)
        -_extract_keywords(text)
    }

    class WebSearchService {
        +client: TavilyClient
        +search(query, max_results)
    }

    class RerankingService {
        +backend: RerankingBackend
        +rerank(query, chunks, top_k)
    }

    RetrievalService --> VectorStore
    CRAGService --> LLMService
    CRAGService --> WebSearchService
    DocumentProcessor --> VectorStore
    RerankingService --> RetrievalService
```

## Data Models Hierarchy

```mermaid
classDiagram
    class QueryRequest {
        +query: str
        +mode: Literal["standard", "crag"]
        +top_k: int = 5
        +enable_reranking: bool = False
    }

    class ChunkMetadata {
        +chunk_id: str
        +source_file: str
        +file_type: str
        +page_number: Optional~int~
        +chunk_index: int
        +total_chunks: int
        +chunk_method: str
        +token_count: int
        +char_count: int
        +content_preview: str
        +keywords: list~str~
        +created_at: datetime
        +processed_at: datetime
    }

    class RetrievedChunk {
        +content: str
        +metadata: ChunkMetadata
        +score: float
    }

    class CRAGEvaluation {
        +relevance_score: float
        +relevance_label: Literal["relevant", "ambiguous", "irrelevant"]
        +confidence: float
        +needs_web_search: bool
        +evaluated_at: datetime
    }

    class CRAGResult {
        +used_web_search: bool
        +evaluation: CRAGEvaluation
        +retrieved_chunks: list~RetrievedChunk~
        +web_results: Optional~list~dict~~
    }

    class QueryResponse {
        +query: str
        +answer: str
        +mode: str
        +sources: list~RetrievedChunk~
        +crag_details: Optional~CRAGResult~
        +response_time_ms: float
        +reranking_used: bool
    }

    RetrievedChunk *-- ChunkMetadata
    CRAGResult *-- CRAGEvaluation
    CRAGResult *-- RetrievedChunk
    QueryResponse *-- RetrievedChunk
    QueryResponse *-- CRAGResult
```



## Configuration Flow

```mermaid
flowchart LR
    ENV[.env File] --> Settings[Settings Class<br/>pydantic-settings]

    Settings --> APIConfig[API Configuration]
    Settings --> LLMConfig[LLM Configuration]
    Settings --> VectorConfig[Vector Store Config]
    Settings --> CRAGConfig[CRAG Configuration]
    Settings --> FeatureFlags[Feature Flags]

    APIConfig --> Host[HOST<br/>PORT]
    LLMConfig --> Model[LLM_MODEL<br/>EMBEDDING_MODEL<br/>OPENAI_API_KEY]
    VectorConfig --> Qdrant[QDRANT_URL<br/>QDRANT_COLLECTION<br/>EMBEDDING_DIMENSIONS]
    CRAGConfig --> Thresholds[RELEVANCE_THRESHOLD<br/>AMBIGUOUS_THRESHOLD<br/>TAVILY_API_KEY]
    FeatureFlags --> Flags[RERANKING_ENABLED<br/>RERANKER_BACKEND]

    style ENV fill:#f0f0f0
    style Settings fill:#e1f5e1
    style APIConfig fill:#e6f3ff
    style LLMConfig fill:#e6f3ff
    style VectorConfig fill:#e6f3ff
    style CRAGConfig fill:#fff4e6
    style FeatureFlags fill:#ffe6e6
```

## External Dependencies

```mermaid
graph TB
    subgraph System["RAG System"]
        API[FastAPI App]
    end

    subgraph Required["Required Services"]
        Qdrant[Qdrant Vector DB<br/>Docker Container<br/>Port 6333]
        OpenAI[OpenAI API<br/>GPT-4 + Embeddings]
    end

    subgraph Optional["Optional Services"]
        Tavily[Tavily Search API<br/>CRAG Web Search]
        Voyage[Voyage AI API<br/>Reranking]
    end

    API -->|REQUIRED| Qdrant
    API -->|REQUIRED| OpenAI
    API -.->|OPTIONAL<br/>If mode=crag/both| Tavily
    API -.->|OPTIONAL<br/>If reranker_backend=voyage| Voyage

    style System fill:#e1f5e1
    style Required fill:#ffe6e6
    style Optional fill:#fff4e6
```

## Deployment Architecture

```mermaid
flowchart TB
    subgraph Localhost["Local Development"]
        FastAPI[FastAPI Server<br/>localhost:8000]
        QdrantDocker[Qdrant Docker<br/>localhost:6333]
    end

    subgraph Cloud["External APIs"]
        OpenAI[OpenAI API]
        Tavily[Tavily API]
        Voyage[Voyage AI API]
    end

    FastAPI <-->|Vector ops| QdrantDocker
    FastAPI -->|LLM calls| OpenAI
    FastAPI -.->|Web search| Tavily
    FastAPI -.->|Reranking| Voyage

    User[User/Client] -->|HTTP| FastAPI

    style Localhost fill:#e6f3ff
    style Cloud fill:#ffe6e6
```



## Performance Optimization Points

```mermaid
flowchart LR
    Query[User Query] --> OptPoints{Optimization<br/>Points}

    OptPoints --> O2[1. Vector Search<br/>Initial top_k]
    OptPoints --> O3[2. Reranking<br/>Local vs API]
    OptPoints --> O4[3. CRAG Evaluation<br/>Cache results?]
    OptPoints --> O5[4. LLM Generation<br/>Model selection]

    O2 -.->|Trade-off| T2[More chunks = better coverage<br/>but slower processing]

    O3 -.->|Local| L3[Free, slower<br/>sentence-transformers]
    O3 -.->|API| A3[Fast, costs $<br/>Voyage AI]

    O4 -.->|Option| OPT4[Cache evaluation<br/>for repeated queries]

    O5 -.->|Fast| F5[gpt-4o-mini<br/>Lower cost]
    O5 -.->|Quality| Q5[gpt-4o<br/>Higher cost]

    style OptPoints fill:#fff4e6
    style O2 fill:#e6f3ff
    style O3 fill:#e6f3ff
    style O4 fill:#e6f3ff
    style O5 fill:#e6f3ff
```

## Key Design Decisions

### 1. **Synchronous Service Layer**
- All services are synchronous (not async)
- FastAPI runs them in thread pool
- Simplifies implementation, sufficient for current scale

### 2. **Pydantic for Everything**
- Request/response validation
- Configuration management (pydantic-settings)
- Data models with strict typing
- Automatic serialization/deserialization

### 3. **Service Initialization Pattern**
```python
# Services initialized at module level (query.py, upload.py)
retrieval_service = RetrievalService()
crag_service = CRAGService()
# Shared across requests, stateless
```

### 4. **Metadata Standardization**
- All chunks (docs + web) use same `ChunkMetadata` structure
- `file_type` distinguishes source ("pdf", "web_search", etc.)
- Enables uniform handling across all RAG modes

### 5. **Error Handling Strategy**
- LLM JSON responses wrapped in try/except with fallbacks
- Pydantic validation errors → 422 responses
- Service errors → 500 with logged details
- Graceful degradation with appropriate fallbacks

## Monitoring & Observability

### Logging Strategy

```python
# Using loguru for structured logging
logger.info(f"Retrieved {len(chunks)} chunks for query")
logger.warning(f"Could not extract page number: {e}")
logger.error(f"Search error: {e}")
```

**Key Log Points:**
- Document processing: chunk count, file info
- Retrieval: chunk count
- CRAG: evaluation score, web search trigger
- Errors: full exception details

### Metrics to Track

| Metric | Location | Purpose |
|--------|----------|---------|
| **Response Time** | query.py | Performance monitoring |
| **Chunk Count** | retrieval.py | Retrieval effectiveness |
| **CRAG Scores** | crag.py | Relevance distribution |
| **Web Search Triggers** | crag.py | CRAG usage patterns |
| **LLM Token Usage** | llm_service.py | Cost tracking |

## Security Considerations

```mermaid
flowchart TD
    Security[Security Measures]

    Security --> S1[API Key Management]
    Security --> S2[Input Validation]
    Security --> S3[File Upload Safety]
    Security --> S4[Data Persistence]

    S1 --> S1A[Env vars only<br/>Never commit .env]
    S1 --> S1B[API keys in pydantic-settings]

    S2 --> S2A[Pydantic validation<br/>on all inputs]
    S2 --> S2B[Type checking<br/>on requests]

    S3 --> S3A[File type validation<br/>PDF/MD/TXT/JSON only]
    S3 --> S3B[Content scanning<br/>via Docling]
    S3 --> S3C[Local storage<br/>uploads/ directory]

    S4 --> S4A[Qdrant local instance<br/>No external exposure]
    S4 --> S4B[No sensitive data<br/>in chunks]

    style Security fill:#ffe6e6
    style S1 fill:#fff4e6
    style S2 fill:#fff4e6
    style S3 fill:#fff4e6
    style S4 fill:#fff4e6
```

## Future Enhancement Opportunities

1. **Async Implementation**
   - Convert services to async/await
   - Parallel LLM calls where possible
   - Async vector operations

2. **Caching Layer**
   - Redis for CRAG evaluation results
   - Embedding cache for repeated queries
   - LLM response cache

3. **Batch Processing**
   - Bulk document uploads
   - Batch query processing
   - Parallel chunk embedding

4. **Advanced Reranking**
   - Multi-stage reranking pipeline
   - Learned reranking models
   - Context-aware reranking

5. **Monitoring Dashboard**
   - Real-time metrics visualization
   - Query analytics
   - Performance trends

6. **Multi-Modal Support**
   - Image embedding and retrieval
   - Audio transcription integration
   - Video content processing

## Getting Started

```bash
# 1. Clone and setup
cd crag-hybrid-rag
cp .env.example .env
# Edit .env with your API keys

# 2. Start Qdrant
docker run -p 6333:6333 -p 6334:6334 qdrant/qdrant

# 3. Install dependencies
uv sync

# 4. Start server
uv run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# 5. Access Swagger UI
open http://localhost:8000/docs

# 6. Upload documents
curl -X POST http://localhost:8000/upload/ \
  -F "file=@document.pdf"

# 7. Query
curl -X POST http://localhost:8000/query/ \
  -H "Content-Type: application/json" \
  -d '{"query": "Your question?", "mode": "both"}'
```

## Related Documentation

- **[workflows/crag_mode.md](./crag_mode.md)** - CRAG workflow details
- **[workflows/hybrid_search.md](./hybrid_search.md)** - Hybrid search details
- **[.env.example](../.env.example)** - Configuration reference
