# Local Docker Testing Guide

Test the Docker image end-to-end locally before pushing to AWS. Run every step
in order — each one validates a specific layer of the stack.

---

## Prerequisites

- Docker running (`docker info` should not error)
- A `.env` file in the project root with real API keys (copy from `.env.example`)
- A PDF or text file handy for upload testing

---

## Step 1 — Prepare Your .env

Make sure `.env` has real values for the two required keys and points Qdrant
at **Qdrant Cloud** (not localhost — your laptop won't have a local Qdrant
instance inside the container):

```env
OPENAI_API_KEY=sk-...
TAVILY_API_KEY=tvly-...

# Use your Qdrant Cloud URL here, NOT http://localhost:6333
QDRANT_URL=https://your-cluster.qdrant.io
QDRANT_API_KEY=your-qdrant-api-key

RERANKER_BACKEND=local
UPLOAD_DIR=/var/app/uploads
```

> **Why not localhost?** The container has its own network. `localhost:6333`
> inside the container would mean a Qdrant running *inside* the container,
> which doesn't exist. Use Qdrant Cloud, or see the optional section at the
> bottom for running a local Qdrant alongside the app container.

---

## Step 2 — Build the Image

```bash
# From the project root (same directory as Dockerfile)
docker build --platform linux/amd64 -t crag-hybrid-rag:local .

OR

docker compose -f docker-compose.local.yml up

OR

docker compose -f docker-compose.local.yml up --build
```

**What to watch for:**
- `uv sync` completing without errors
- The cross-encoder model download line:
  ```
  Downloading cross-encoder/ms-marco-MiniLM-L-6-v2 ...
  ```
- Final line: `Successfully built <image-id>`

**Expected build time:** 5–15 min on first build (model download + deps).
Subsequent builds use the layer cache and take ~30 seconds.

---

## Step 3 — Run the Container

```bash
docker run --rm \
  --name crag-test \
  --env-file .env \
  -p 8000:8000 \
  crag-hybrid-rag:local
```

**Expected startup output:**
```
INFO     | app.main:... - Starting CRAG Hybrid RAG API
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

The app should be ready within ~10–30 seconds (cross-encoder loads into RAM at
startup). Leave this terminal open and open a new one for the tests below.

---

## Step 4 — Health Check

```bash
curl -s http://localhost:8000/health | python3 -m json.tool
```

**Expected:**
```json
{
    "status": "healthy"
}
```

If this fails, the container didn't start correctly — check the container logs
in the first terminal.

---

## Step 5 — Root Endpoint

```bash
curl -s http://localhost:8000/ | python3 -m json.tool
```

**Expected:**
```json
{
    "message": "CRAG + Self-Reflective RAG API",
    "docs": "/docs",
    "endpoints": {
        "upload": "/upload/",
        "query": "/query/",
        "compare": "/query/compare"
    }
}
```

---

## Step 6 — Open Swagger UI

Open in your browser:

```
http://localhost:8000/docs
```

You should see the full interactive API documentation. This confirms FastAPI
is serving correctly and all routes are registered.

---

## Step 7 — Upload a Document

Replace `sample/your-file.pdf` with any PDF or `.txt` file you have:

```bash
curl -s -X POST http://localhost:8000/upload/ \
  -F "file=@sample/your-file.pdf" \
  | python3 -m json.tool
```

**Expected (success):**
```json
{
    "file_id": "abc123...",
    "filename": "your-file.pdf",
    "file_type": "pdf",
    "chunks_created": 12,
    "status": "success"
}
```

**What this tests:**
- Docling PDF extraction
- OpenAI embedding API call
- Qdrant upsert (dense + sparse vectors)

If `chunks_created` is 0 or you get a 500, check the container logs for the
specific error (usually a Qdrant connection issue or missing API key).

---

## Step 8 — Query (Standard Mode)

```bash
curl -s -X POST http://localhost:8000/query/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is the main topic of the document?",
    "mode": "standard",
    "search_mode": "hybrid",
    "top_k": 5,
    "enable_reranking": false
  }' | python3 -m json.tool
```

**Expected:**
```json
{
    "query": "What is the main topic of the document?",
    "answer": "...",
    "mode": "standard",
    "search_mode": "hybrid",
    "sources": [...],
    "crag_details": null,
    "response_time_ms": 1234
}
```

---

## Step 9 — Query (CRAG Mode)

CRAG mode evaluates retrieved chunks and falls back to Tavily web search if
context is irrelevant. Use a query where the answer is *in* your uploaded doc:

```bash
curl -s -X POST http://localhost:8000/query/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is the main topic of the document?",
    "mode": "crag",
    "search_mode": "hybrid",
    "top_k": 5,
    "enable_reranking": false
  }' | python3 -m json.tool
```

**Check `crag_details` in the response:**
```json
"crag_details": {
    "relevance_score": 0.85,
    "relevance_label": "relevant",
    "confidence": 0.9,
    "needs_web_search": false
}
```

Now try a query about something NOT in the document (should trigger web search):

```bash
curl -s -X POST http://localhost:8000/query/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is the current price of Bitcoin?",
    "mode": "crag",
    "search_mode": "hybrid",
    "top_k": 5,
    "enable_reranking": false
  }' | python3 -m json.tool
```

**Expected:** `"needs_web_search": true` and `"relevance_label": "irrelevant"`.

---

## Step 10 — Query with Reranking

```bash
curl -s -X POST http://localhost:8000/query/ \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is the main topic of the document?",
    "mode": "standard",
    "search_mode": "hybrid",
    "top_k": 5,
    "enable_reranking": true
  }' | python3 -m json.tool
```

This loads the cross-encoder from the pre-baked HuggingFace cache. If it
errors, the model wasn't baked into the image — rebuild.

---

## Step 11 — Compare Mode

```bash
curl -s "http://localhost:8000/query/compare?query=What+is+the+main+topic" \
  | python3 -m json.tool
```

Returns both standard and CRAG responses side-by-side. Confirms both code
paths work in a single call.

---

## Step 12 — Check Container Logs

While the container is running, in a separate terminal:

```bash
docker logs crag-test
```

Or follow live:

```bash
docker logs -f crag-test
```

Look for:
- No `ERROR` or `CRITICAL` lines
- Successful embedding calls: `EmbeddingService: embedded X texts`
- Successful Qdrant calls: `VectorStore: upserted X points`

---

## Step 13 — Inspect the Running Container (optional)

```bash
# Open a shell inside the running container
docker exec -it crag-test bash

# Verify the venv is intact
/app/.venv/bin/python --version

# Verify the HuggingFace model cache is present
ls /home/appuser/.cache/huggingface/hub/

# Check the uploads directory exists
ls -la /var/app/uploads/

exit
```

---

## Step 14 — Stop the Container

```bash
docker stop crag-test
```

The `--rm` flag in Step 3 means the container is automatically removed on stop.

---

## Checklist

- [ ] `docker build` completes without errors
- [ ] Container starts and logs show uvicorn listening on `:8000`
- [ ] `GET /health` → `{"status": "healthy"}`
- [ ] `GET /docs` renders Swagger UI in browser
- [ ] `POST /upload/` returns `chunks_created > 0`
- [ ] `POST /query/` (standard) returns an answer with sources
- [ ] `POST /query/` (crag, in-doc query) → `needs_web_search: false`
- [ ] `POST /query/` (crag, off-topic query) → `needs_web_search: true`
- [ ] `POST /query/` with `enable_reranking: true` works without error
- [ ] No ERROR lines in `docker logs`

All boxes checked → safe to deploy to AWS.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `docker build` fails on `uv sync` | `uv.lock` missing or corrupted | Run `uv lock` locally first, then rebuild |
| Container exits immediately | Missing required env var | Check `.env` has `OPENAI_API_KEY` and `TAVILY_API_KEY` |
| `{"detail": "...ValidationError..."}` at startup | Same as above | Check `.env` values |
| `curl: Connection refused` | Container not started yet | Wait 15–30s for model load, then retry |
| `POST /upload/` returns 500 | Qdrant unreachable | Confirm `QDRANT_URL` points to Qdrant Cloud, not localhost |
| `POST /upload/` returns 500 | OpenAI API key invalid | Check `OPENAI_API_KEY` in `.env` |
| `chunks_created: 0` | Docling failed to parse file | Try a plain `.txt` file to isolate the issue |
| CRAG never triggers web search | Relevance threshold too high | Temporarily lower `CRAG_AMBIGUOUS_THRESHOLD=0.9` in `.env` |
| Reranking returns 500 | Cross-encoder not baked in image | Rebuild — check the `CrossEncoder(...)` line ran during build |
| OOM / container killed | Not enough Docker memory | Docker Desktop → Settings → Resources → increase to 8 GB RAM |

---

## Optional: Run Qdrant Locally Alongside the App

If you want a fully self-contained local test (no Qdrant Cloud):

```bash
# Terminal 1 — start Qdrant
docker run --rm --name qdrant -p 6333:6333 qdrant/qdrant:latest

# Terminal 2 — start the app, pointing at host Qdrant
# host.docker.internal resolves to your Mac's localhost from inside a container
docker run --rm \
  --name crag-test \
  --env-file .env \
  -e QDRANT_URL=http://host.docker.internal:6333 \
  -e QDRANT_API_KEY= \
  -p 8000:8000 \
  crag-hybrid-rag:local
```

> `host.docker.internal` is a Docker Desktop special hostname that resolves to
> the host machine. It works on Mac and Windows but not Linux (use
> `--network host` or `--add-host host.docker.internal:host-gateway` on Linux).
