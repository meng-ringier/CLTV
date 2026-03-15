import interactive_gam_api
import gzip
import shutil

project_id='authrion-app'
secret_id='ringier_oauth_credential'
client=interactive_gam_api.AdManagerV1Client(project_id, secret_id)

table_name='test'
network_code='21823152020'
report_start_date='2024-01-01'
report_end_date='2024-01-31'
report_definition, report_name =client.create_report(table_name, network_code, report_start_date, report_end_date)
report_result_endpoint = client.run_report_export(report_name)
header, report_refined_file =client.save_report_to_gz(report_result_endpoint, report_definition)




with gzip.open(report_refined_file, "rb") as f_in:
    with open(report_refined_file.replace(".gz",""), "wb") as f_out:
        shutil.copyfileobj(f_in, f_out)