from google.ads import admanager_v1
from google.longrunning.operations_pb2 import GetOperationRequest
from google.ads.admanager_v1.types import ReportDefinition, report_value
from datetime import datetime
from google.type import date_pb2
from google.ads.admanager_v1.types import RunReportResponse
import time
import gzip
import csv
import tempfile
from google.cloud import secretmanager
import data_util
import logging
import json
from datetime import datetime

logging.basicConfig(level=logging.INFO)


def get_value(col_name, val):
    val_str = str(val).strip()

    if col_name.lower() == 'date':
        value= datetime.strptime(val_str.split(":")[1].strip(), "%Y%m%d").date()
    else:
        parts = val_str.split(":", 1)
        if parts[0].lower() == "string_value":
            # Take second part and remove surrounding quotes if present
            value = parts[1].strip()
            if value.startswith('"') and value.endswith('"'):
                value = value[1:-1]
        else:
            value= str(val).split(":")[1].strip()

    return value


def get_secret_data(project_id, secret_id, version_id="latest"):
    client = secretmanager.SecretManagerServiceClient()
    secret_detail = (
        f"projects/{project_id}/secrets/{secret_id}/versions/{version_id}"
    )
    response = client.access_secret_version(request={"name": secret_detail})
    data = response.payload.data.decode("UTF-8")
    return data

class AdManagerV1Client:
    def __init__(self, project_id, credential_name):
        credentials_json=json.loads(data_util.get_secret_data(project_id=project_id, secret_id=credential_name))
        creds = data_util.get_credentials(credentials_json)
        self.client = admanager_v1.ReportServiceClient(credentials=creds)

    def create_report(self, table_name, network_code, report_start_date, report_end_date):
        with open(f"interactive_report_query/{table_name}.json", "r", encoding="utf-8") as file:
            report_json = json.load(file)

        dimensions_enum = [
            getattr(ReportDefinition.Dimension, dim.upper())
            for dim in report_json.get("dimensions", [])
        ]

        metrics_enum = [
            getattr(ReportDefinition.Metric, metric.upper())
            for metric in report_json.get("metrics", [])
        ]

        filters=None


        report_start_date = datetime.strptime(report_start_date, "%Y-%m-%d").date()
        report_end_date = datetime.strptime(report_end_date, "%Y-%m-%d").date()


        # Build Date protobufs
        start_date_pb = date_pb2.Date(year=report_start_date.year, month=report_start_date.month, day=report_start_date.day)
        end_date_pb = date_pb2.Date(year=report_end_date.year, month=report_end_date.month, day=report_end_date.day)


        # Initialize request argument(s)
        report = admanager_v1.Report(
            display_name=f"{table_name}_{report_start_date}_{report_end_date}",
            report_definition=ReportDefinition(
                dimensions=dimensions_enum,
                metrics=metrics_enum,
                filters=filters,
                date_range=admanager_v1.ReportDefinition.DateRange(
                    fixed=admanager_v1.ReportDefinition.DateRange.FixedDateRange(
                        start_date=start_date_pb,
                        end_date=end_date_pb,
                    )
                ),
                report_type=ReportDefinition.ReportType.HISTORICAL,
            )
        )

        request = admanager_v1.CreateReportRequest(
            parent=f"networks/{network_code}",
            report=report,
        )

        # Make the request
        response = self.client.create_report(request=request)

        return report_json, response.name

    def run_report_export(self, report_name, poll_interval=5):
        response = self.client.run_report(name=report_name)

        # Check if the long-running operation has completed
        operation = self.client.get_operation(
            GetOperationRequest(name=response.operation.name))
        while True:
            operation = self.client.get_operation(
                GetOperationRequest(name=response.operation.name)
            )
            if operation.done:
                # Deserialize the final response
                run_report_response = RunReportResponse.deserialize(operation.response.value)
                print(run_report_response)
                return run_report_response.report_result
            else:
                print("Report not ready yet, waiting...")
                time.sleep(poll_interval)

    def save_report_to_gz(self, report_result_endpoint, report_definition):
        # Create temporary gzipped CSV file
        output_file = tempfile.NamedTemporaryFile(suffix='.csv.gz', delete=False)
        print(f"Save result to {output_file.name}")
        header = report_definition["dimensions"] + report_definition["metrics"]

        with gzip.open(output_file.name, "wt", newline="", encoding="utf-8") as gzfile:
            writer = csv.writer(gzfile)
            # Write header
            writer.writerow(header)

            # Prepare request
            request = admanager_v1.FetchReportResultRowsRequest(
                name=report_result_endpoint,
                page_size=10000
            )

            # Fetch rows
            page_result = self.client.fetch_report_result_rows(request=request)

            page_index = 0
            row_index = 0

            # Iterate over pages
            for page in page_result.pages:
                page_index += 1
                print(f"Processing page {page_index} with {len(page.rows)} rows")

                # Iterate rows in the page
                for row in page.rows:
                    row_index += 1
                    row_dict = {}

                    # Map dimension values
                    for col_name, val in zip(report_definition["dimensions"], row.dimension_values):
                        row_dict[col_name] = get_value(col_name, val)

                    # Map metric values
                    metric_values = row.metric_value_groups[0].primary_values
                    for col_name, val in zip(report_definition["metrics"], metric_values):
                        row_dict[col_name] = get_value(col_name, val)

                    # Write row in the same order as header
                    row_values = [row_dict.get(col, "") for col in header]
                    # print(row_values)
                    writer.writerow(row_values)

        return header, output_file.name

    def get_report_data(self, network_code, table_name, report_start_date, report_end_date):
        report_definition, report_name = self.create_report(network_code, table_name, report_start_date,
                                                            report_end_date)
        report_result_endpoint = self.run_report_export(report_name)
        return  self.save_report_to_gz(report_result_endpoint, report_definition)


