import os
import sys
import httpx

BACKEND_URL = "https://quiz-vance-redesign-backend.fly.dev"

def check_health():
    res = httpx.get(f"{BACKEND_URL}/telegram/health")
    print("Telegram Health Endpoint Response:")
    print(res.json())

if __name__ == "__main__":
    check_health()
