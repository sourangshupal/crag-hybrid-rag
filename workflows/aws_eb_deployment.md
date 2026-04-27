# AWS Elastic Beanstalk Deployment Architecture

## Deployment Pipeline

```mermaid
flowchart LR
    DEV["Developer Machine\n(git push deploy/aws-eb)"]
    GH["GitHub Actions\nubuntu-latest runner"]
    ECR["Amazon ECR\ncrag-hybrid-rag\n:SHA + :latest"]
    EB["Elastic Beanstalk\ncrag-hybrid-prod\nt3.large · Docker"]
    EC2["EC2 Instance\nDocker container\nuvicorn :8000"]

    DEV -->|push| GH
    GH -->|docker build + push| ECR
    GH -->|create-application-version\nupdate-environment| EB
    EB -->|docker pull :latest| ECR
    EB -->|runs| EC2
```

---

## Runtime Request Flow

```mermaid
flowchart TD
    CLIENT["Client\n(browser / curl)"]
    NGX["Nginx\nport 80\n300s timeout\n50MB upload limit"]
    APP["FastAPI App\nuvicorn :8000\n--workers 1"]

    subgraph SERVICES["App Services"]
        EMBED["EmbeddingService\nOpenAI text-embedding-3-small"]
        CRAG["CRAGService\nRelevance evaluation\n+ web search fallback"]
        RERANK["RerankingService\ncross-encoder/ms-marco-MiniLM-L-6-v2\n(pre-baked in image)"]
        SPARSE["SparseVectorService\nBM25 sparse vectors"]
    end

    subgraph EXTERNAL["External Services"]
        QDRANT["Qdrant Cloud\nDense + Sparse vectors\nHybrid RRF search"]
        OPENAI["OpenAI API\nGPT-4o-mini + embeddings"]
        TAVILY["Tavily API\nWeb search (CRAG fallback)"]
    end

    CLIENT -->|POST /upload/ or /query/| NGX
    NGX --> APP
    APP --> EMBED
    APP --> CRAG
    APP --> RERANK
    APP --> SPARSE
    EMBED --> OPENAI
    CRAG --> OPENAI
    CRAG --> TAVILY
    RERANK --> RERANK
    SPARSE --> QDRANT
    EMBED --> QDRANT
```

---

## IAM Permissions Model

```mermaid
flowchart TD
    subgraph GITHUB["GitHub Actions Runner"]
        GHA_USER["IAM User\nAWS_ACCESS_KEY_ID\nAWS_SECRET_ACCESS_KEY"]
    end

    subgraph PERMISSIONS["IAM Permissions"]
        ECR_PUSH["ECR: PutImage\nInitiateLayerUpload\nCompleteLayerUpload\netc."]
        S3_PUT["S3: PutObject\nGetObject\nelasticbeanstalk-*/*"]
        EB_DEPLOY["EB: CreateApplicationVersion\nUpdateEnvironment\nDescribeEnvironments"]
        STS["STS: GetCallerIdentity"]
    end

    subgraph EC2_ROLE["EC2 Instance Role"]
        ECR_PULL["AmazonEC2ContainerRegistryReadOnly\n(managed policy)"]
    end

    GHA_USER --> ECR_PUSH
    GHA_USER --> S3_PUT
    GHA_USER --> EB_DEPLOY
    GHA_USER --> STS
    EC2_ROLE --> ECR_PULL
```

---

## Re-deploy Workflow (Iterative Development)

```mermaid
flowchart LR
    CODE["Edit code\nlocally"]
    PUSH["git push\ndeploy/aws-eb"]
    BUILD["GitHub Actions\ndocker build\n--platform linux/amd64"]
    PUSH_ECR["docker push\n:SHA + :latest"]
    ZIP["zip deploy.zip\nDockerrun + .platform\n+ .ebextensions"]
    S3["s3 cp deploy.zip\nelasticbeanstalk bucket"]
    EB_VER["create-application-version"]
    EB_UPD["update-environment\n+ inject env vars"]
    POLL["Poll 30s × 40\n(20 min max)"]
    READY["Status=Ready\nHealth=Green\nDeploy complete!"]

    CODE --> PUSH --> BUILD --> PUSH_ECR --> ZIP --> S3 --> EB_VER --> EB_UPD --> POLL --> READY
```

---

## Container Startup Sequence

```mermaid
sequenceDiagram
    participant EB as Elastic Beanstalk
    participant DC as Docker
    participant APP as FastAPI App
    participant HF as HuggingFace Cache
    participant QD as Qdrant Cloud

    EB->>DC: docker pull crag-hybrid-rag:latest
    DC->>DC: Extract image layers
    EB->>DC: docker run --env OPENAI_API_KEY=... (port 8000)
    DC->>APP: Start uvicorn (--workers 1)
    APP->>HF: Load cross-encoder from /home/appuser/.cache/huggingface
    Note over APP,HF: Pre-baked in image — no network call
    APP->>QD: Verify Qdrant connection
    APP->>APP: Register FastAPI routes
    APP-->>EB: Listening on :8000
    EB->>APP: GET /health
    APP-->>EB: {"status":"healthy"} → Health=Green
```

---

*Author: Sourangshu Pal*
