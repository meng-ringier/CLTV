from google.analytics.data_v1beta import BetaAnalyticsDataClient
from google.analytics.data_v1beta.types import RunReportRequest
from google.oauth2.credentials import Credentials
import requests
from google.analytics.data_v1beta.types import RunReportRequest, DateRange, Dimension, Metric
from google.cloud import secretmanager
import json
from google.analytics.data_v1beta.types import FilterExpression, Filter
import csv


def generate_refresh_token(client_id, client_secret, redirect_uri, code):
    token_url = "https://oauth2.googleapis.com/token"

    data = {
        "code": code,
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }

    response = requests.post(token_url, data=data)
    tokens = response.json()

    print(tokens)


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
        scopes=["https://www.googleapis.com/auth/analytics.readonly"]
    )
    return creds


def parse_filter_string(filter_str: str) -> FilterExpression:
    # Very basic parser: expects "field operator value"
    # Example: 'pagePath contains "/fr/"'
    parts = filter_str.split(" ", 2)  # split into 3 parts
    if len(parts) != 3:
        raise ValueError("Filter string must be in format 'field operator value'")

    field, operator, value = parts
    value = value.strip('"')  # remove quotes if present

    # Map operator string to GA4 MatchType
    match_type_map = {
        "contains": Filter.StringFilter.MatchType.CONTAINS,
        "exact": Filter.StringFilter.MatchType.EXACT,
        "begins_with": Filter.StringFilter.MatchType.BEGINS_WITH,
        "ends_with": Filter.StringFilter.MatchType.ENDS_WITH
    }

    if operator.lower() not in match_type_map:
        raise ValueError(f"Unsupported operator: {operator}")

    return FilterExpression(
        filter=Filter(
            field_name=field,
            string_filter=Filter.StringFilter(
                match_type=match_type_map[operator.lower()],
                value=value
            )
        )
    )

def run_ga4_report(credentials_json, property_id, dimensions, metrics, start_date, end_date, dimension_filter):
    creds = get_credentials(credentials_json)
    client = BetaAnalyticsDataClient(credentials=creds)

    request = RunReportRequest(
        property=f"properties/{property_id}",
        dimensions=[Dimension(name=d) for d in dimensions],
        metrics=[Metric(name=m) for m in metrics],
        date_ranges=[DateRange(start_date=start_date, end_date=end_date)],
    )

    if dimension_filter:
        request.dimension_filter = parse_filter_string(dimension_filter)  # make sure filters is GA4 FilterExpression

    response = client.run_report(request)

    with open("ga4_report.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)

        # Write header
        header = [d.name for d in request.dimensions] + [m.name for m in request.metrics]
        writer.writerow(header)


        # Write data rows
        for row in response.rows:
            print(row)
            row_data = [dim.value for dim in row.dimension_values] + [met.value for met in row.metric_values]
            writer.writerow(row_data)

    print("GA4 report saved to ga4_report.csv")