import os
import requests
import json
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Get environment variables
API_KEY = os.environ.get('VLLM_API_KEY')
MODEL = os.environ.get('MODEL')
API_BASE_URL = os.environ.get('API_BASE_URL', 'http://localhost')
MESSAGE = "Was ist die Hauptstadt von Frankreich?"  # Example message

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

