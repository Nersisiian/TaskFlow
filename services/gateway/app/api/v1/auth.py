from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException
from jose import jwt
from ...config import get_settings, Settings

router = APIRouter(prefix="/auth", tags=["auth"])

# Dummy user store for demonstration
USERS = {
    "admin": {"password": "adminpass", "role": "admin"},
    "user": {"password": "userpass", "role": "user"}
}

@router.post("/login")
async def login(username: str, password: str, settings: Settings = Depends(get_settings)):
    user = USERS.get(username)
    if not user or user["password"] != password:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    payload = {
        "sub": username,
        "role": user["role"],
        "exp": datetime.utcnow() + timedelta(minutes=settings.access_token_expire_minutes)
    }
    token = jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    return {"access_token": token, "token_type": "bearer"}
