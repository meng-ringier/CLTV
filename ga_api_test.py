import ga_api
import json
import data_util

credentials_json=json.loads(data_util.get_secret_data(project_id='authrion-app',secret_id='ringier_oauth_credential'))
property_id='185520714'
dimensions=['deviceCategory','customUser:user_status','customUser:product_name']

metrics=['totalUsers','newUsers','sessions','screenPageViews','eventCount']
start_date='2024-01-01'
end_date='2024-01-31'
dimension_filter=None
# dimension_filter='pagePath contains "/fr/"'

ga_api.run_ga4_report(credentials_json, property_id, dimensions, metrics, start_date, end_date, dimension_filter)