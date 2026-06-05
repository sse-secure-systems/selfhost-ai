import os
import sys
import requests
import json
from pathlib import Path
from dotenv import load_dotenv

# Explicitly load the root .env so a stray local .env can never shadow it
load_dotenv(Path(__file__).resolve().parents[2] / ".env")

# Get environment variables
API_KEY = os.environ.get('VLLM_API_KEY')
MODEL = os.environ.get('MODEL')
API_BASE_URL = os.environ.get('API_BASE_URL', 'http://localhost')
MESSAGE = sys.argv[1] if len(sys.argv) > 1 else "Was ist die Hauptstadt von Frankreich?"

# API endpoint
url = f"{API_BASE_URL.rstrip('/')}/v1/chat/completions"

# Headers
headers = {
    "Content-Type": "application/json",
    "Authorization": f"Bearer {API_KEY}"
}

# Request body
data = {
    "model": MODEL,
    "messages": [
        {"role": "user", "content": MESSAGE}
    ]
}

# Make the POST request
response = requests.post(url, headers=headers, json=data)

# Print response
print(f"Status Code: {response.status_code}")
print(f"Response: {response.text}")

