from google.cloud import secretmanager
import json
from google.oauth2.credentials import Credentials

def get_secret_data(project_id, secret_id, version_id="latest"):
    client = secretmanager.SecretManagerServiceClient()
    secret_detail = (
        f"projects/{project_id}/secrets/{secret_id}/versions/{version_id}"
    )
    response = client.access_secret_version(request={"name": secret_detail})
    data = response.payload.data.decode("UTF-8")
    return data

def get_credentials(credentials_json):
    creds = Credentials(
        None,  # access_token is None; it will refresh automatically
        refresh_token=credentials_json.get("refresh_token"),
        token_uri="https://oauth2.googleapis.com/token",
        client_id=credentials_json.get("client_id"),
        client_secret=credentials_json.get("client_secret"),
        scopes=["https://www.googleapis.com/auth/analytics.readonly","https://www.googleapis.com/auth/admanager"]
    )
    return creds