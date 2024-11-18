import json
from google.cloud import bigquery
from google.oauth2 import service_account
from datetime import datetime, timedelta
from collections import defaultdict

# Parse the log entry to extract fields
def parse_log_entry(log_entry):
    components = log_entry.split(', ')
    parsed_data = {}
    for component in components:
        if ':' in component:
            key, value = component.split(': ', 1)
            parsed_data[key.strip()] = value.strip()
    return parsed_data

# Calculate the start of the next hour as the aggregation interval end
def calculate_hourly_key(timestamp_str):
    timestamp = datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S")
    next_hour = (timestamp + timedelta(hours=1)).replace(minute=0, second=0, microsecond=0)
    return next_hour.isoformat()

# Aggregate log entries by hour and status code
def aggregate_values(parsed_data, aggregates):
    attribute = parsed_data.get('Attribute', 'Unknown')
    client = parsed_data.get('Client', 'Unknown')
    customer_name = parsed_data.get('Customer Name', 'Unknown')
    carrier_name = parsed_data.get('Carrier Name', 'Unknown')
    method = parsed_data.get('Method', 'Unknown')
    status = parsed_data.get('Status')
    # latency = float(parsed_data.get('Latency', '0'))  # Default to 0 if latency is missing

    # Parse and clean the latency field
    latency_value = parsed_data.get('Latency', '0').replace('ms', '').strip()
    latency = float(latency_value) if latency_value else 0  # Default to 0 if latency is missing or invalid
    
    # Calculate the hourly key
    timestamp_str = parsed_data.get('Timestamp', '')
    hourly_key = calculate_hourly_key(timestamp_str) if timestamp_str else None

    # Create a unique key for aggregation
    key = (hourly_key, customer_name, client, carrier_name, attribute, method)
    
    # Initialize the counts if the key doesn't exist
    if key not in aggregates:
        aggregates[key] = {
            '200': 0, '404': 0, 'other': 0,
            'latency_sum': 0, 'request_count': 0
        }
    
    # Increment the appropriate count based on status
    if status == '200':
        aggregates[key]['200'] += 1
    elif status == '404':
        aggregates[key]['404'] += 1
    else:
        aggregates[key]['other'] += 1

    # Update latency and request count
    aggregates[key]['latency_sum'] += latency
    aggregates[key]['request_count'] += 1

def push_to_bigquery(aggregates, client):
    table_ref = f"{client.project}.test_aggregates.kong_aggregate"
    rows_to_insert = []

    for (hourly_key, customer_name, client_name, carrier_name, attribute, method), counts in aggregates.items():
        # Calculate average latency
        avg_latency = (
            counts['latency_sum'] / counts['request_count']
            if counts['request_count'] > 0 else 0
        )
        
        # Add rows for each transaction type
        if counts['200'] > 0:
            rows_to_insert.append({
                "datatime": hourly_key,
                "carrier_name": customer_name,
                "client": client_name,
                "customer_name": carrier_name,
                "attributes": attribute,
                # "Method": method,
                "transaction_type": "Successful",
                "transaction_type_count": counts['200'],
                "total_full_rate_billable_transaction": counts['200'],
                "total_lower_rate_billable_transaction": counts['404'],
                "total_no_billable_transaction": counts['other'],
                "avg_latency": avg_latency
            })
            

        if counts['404'] > 0:
            rows_to_insert.append({
                "datatime": hourly_key,
                "customer_name": carrier_name,
                "client": client_name,
                "carrier_name": customer_name,
                "attributes": attribute,
                #"Method": method,
                "transaction_type": "Unsuccessful Transactions",
                "transaction_type_count": counts['404'],
                "total_full_rate_billable_transaction": counts['200'],
                "total_lower_rate_billable_transaction": counts['404'],
                "total_no_billable_transaction": counts['other'],
                "avg_latency": avg_latency
            })

        if counts['other'] > 0:
            rows_to_insert.append({
                "datatime": hourly_key,
                "customer_name": carrier_name,
                "client": client_name,
                "carrier_name": customer_name,
               "attributes": attribute,
                "transaction_type": "User not Supported",
                "transaction_type_count": counts['other'],
                "total_full_rate_billable_transaction": counts['200'],
                "total_lower_rate_billable_transaction": counts['404'],
                "total_no_billable_transaction": counts['other'],
                "avg_latency": avg_latency
            })

    # Insert rows into BigQuery
    errors = client.insert_rows_json(table_ref, rows_to_insert)
    if errors:
        print(f"Errors occurred while inserting rows: {errors}")
    else:
        print("Rows inserted successfully.")

# Process the log file and aggregate by hour
def process_log_file(file_path, client):
    aggregates = defaultdict(dict)

    with open(file_path, 'r') as log_file:
        for line in log_file:
            log_entry = line.strip()
            if log_entry:
                parsed_data = parse_log_entry(log_entry)
                aggregate_values(parsed_data, aggregates)

    print(f"Final Aggregates: {aggregates}")
    push_to_bigquery(aggregates, client)

# Main function to set up BigQuery client and start processing
def main():
    key_path = '/home/gabrielv/service-account-file.json'
    credentials = service_account.Credentials.from_service_account_file(
        key_path,
        scopes=["https://www.googleapis.com/auth/bigquery"]
    )
    client = bigquery.Client(credentials=credentials, project='sherlock-004')
    log_file_path = '/usr/local/kong/logs/custom_api_transaction.log'
    process_log_file(log_file_path, client)

if __name__ == "__main__":
    main()
