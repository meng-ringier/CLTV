from google.cloud import secretmanager


def get_secret_data(project_id, secret_id, version_id="latest"):
    client = secretmanager.SecretManagerServiceClient()
    secret_detail = (
        f"projects/{project_id}/secrets/{secret_id}/versions/{version_id}"
    )
    response = client.access_secret_version(request={"name": secret_detail})
    data = response.payload.data.decode("UTF-8")
    return data


def process():
    print("Process data")