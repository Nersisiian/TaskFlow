from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .middleware.rate_limit import RateLimitMiddleware
from .api.v1 import auth, tasks

app = FastAPI(title="TaskFlow API Gateway", version="1.0.0")

app.add_middleware(RateLimitMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api/v1")
app.include_router(tasks.router, prefix="/api/v1")

@app.get("/health")
async def health():
    return {"status": "ok"}
