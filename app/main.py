from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api import upload, query
from app.config import get_settings
from loguru import logger
import sys

# Configure logging
logger.remove()
logger.add(
    sys.stdout,
    format="<green>{time:YYYY-MM-DD HH:mm:ss}</green> | <level>{level: <8}</level> | <cyan>{name}</cyan>:<cyan>{function}</cyan> - <level>{message}</level>",
    level="INFO"
)

settings = get_settings()

app = FastAPI(
    title="RAG with Hybrid Search",
    description="(CRAG) with hybrid dense + sparse retrieval + reranker",
    version="1.0.0"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(upload.router)
app.include_router(query.router)


@app.get("/")
async def root():
    return {
        "message": "CRAG + Self-Reflective RAG API",
        "docs": "/docs",
        "endpoints": {
            "upload": "/upload/",
            "query": "/query/",
            "compare": "/query/compare"
        }
    }


@app.get("/health")
async def health():
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
