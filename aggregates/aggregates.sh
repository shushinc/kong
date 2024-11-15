#!/bin/bash

# Define the log file path
LOG_FILE="/usr/local/kong/logs/custom_api_transaction.log"

# Variables to store aggregated data by hour
declare -A customer_200_count
declare -A customer_404_count
declare -A customer_other_non200_count

# Function to parse the log and aggregate data by hour
aggregate_logs_by_hour() {
    # Extract and group logs by each hour
    while IFS= read -r line; do
        # Extract the timestamp of the log entry
        timestamp=$(echo "$line" | grep -oP 'Timestamp: \K[^,]+')
        
        # Extract the hour from the timestamp (e.g., "2024-10-22 11:00:00")
        hour=$(date -d "$timestamp" "+%Y-%m-%d %H:00:00")
        # Extract the necessary fields from the log line using regex
        attribute=$(echo "$line" | grep -oP 'Attribute: \K[^,]+')
        customer_name=$(echo "$line" | grep -oP 'Customer Name: \K[^,]+')
        client=$(echo "$line" | grep -oP 'Client: \K[^,]+')
        carrier_name=$(echo "$line" | grep -oP 'Carrier Name: \K[^,]+')
        method=$(echo "$line" | grep -oP 'Method: \K[^,]+')
        status=$(echo "$line" | grep -oP 'Status: \K[0-9]+')

        # Create a unique key combining the hour with other fields
        key="$hour|$customer_name|$client|$carrier_name|$attribute|$method"
        
        # Increment the count based on the status code
        if [[ "$status" -eq 200 ]]; then
            customer_200_count["$key"]=$((customer_200_count["$key"] + 1))
        elif [[ "$status" -eq 404 ]]; then
            customer_404_count["$key"]=$((customer_404_count["$key"] + 1))
        else
            customer_other_non200_count["$key"]=$((customer_other_non200_count["$key"] + 1))
        fi
    done < "$LOG_FILE"
}

print_aggregated_results() {
    printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15s %-15s %-15s %-30s %-25s\n" "Timestamp Interval" "Customer Name" "Client" "Carrier Name" "Attribute" "Method" "200 Status Count" "404 Status Count" "Other Non-200 Status" "Transaction Type" "Transaction Type Count"
    printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15s %-15s %-15s %-30s %-25s\n" "------------------" "-------------" "------" "------------" "---------" "------" "---------------" "---------------" "--------------------" "--------------------" "----------------------"

    # Loop through the associative array and print the table rows
    for key in "${!customer_200_count[@]}"; do
        # Split the key into its components
        IFS='|' read -r hour customer_name client carrier_name attribute method <<< "$key"
        
        # Calculate the next hour (end of the interval)
        next_hour=$(date -d "@$(( $(date -d "$hour" +%s) + 3600 ))" "+%Y-%m-%d %H:00:00")
        
        # Print row for 200 Status Count with Transaction Type as "Successful" and the actual count
        printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15d %-15s %-15s %-30s %-25s\n" "$next_hour" "$customer_name" "$client" "$carrier_name" "$attribute" "$method" "${customer_200_count[$key]}" "0" "0" "Successful" "${customer_200_count[$key]}"

        # Print row for 404 Status Count, if exists, with Transaction Type as "Unsuccessful Transactions" and the actual count
        if [[ -n "${customer_404_count[$key]}" ]]; then
            printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15s %-15d %-15s %-30s %-25s\n" "$next_hour" "$customer_name" "$client" "$carrier_name" "$attribute" "$method" "0" "${customer_404_count[$key]}" "0" "Unsuccessful Transactions" "${customer_404_count[$key]}"
        fi

        # Print row for Other Non-200 Status Count, if exists, with Transaction Type as "User not Supported" and the actual count
        if [[ -n "${customer_other_non200_count[$key]}" ]]; then
            printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15s %-15s %-15d %-30s %-25s\n" "$next_hour" "$customer_name" "$client" "$carrier_name" "$attribute" "$method" "0" "0" "${customer_other_non200_count[$key]}" "User not Supported" "${customer_other_non200_count[$key]}"
        fi
    done

    # Additional checks for 404 and non-200-only entries
    for key in "${!customer_404_count[@]}"; do
        if [[ -z "${customer_200_count[$key]}" ]]; then
            IFS='|' read -r hour customer_name client carrier_name attribute method <<< "$key"
            next_hour=$(date -d "@$(( $(date -d "$hour" +%s) + 3600 ))" "+%Y-%m-%d %H:00:00")
            printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15s %-15d %-15s %-30s %-25s\n" "$next_hour" "$customer_name" "$client" "$carrier_name" "$attribute" "$method" "0" "${customer_404_count[$key]}" "0" "Unsuccessful Transactions" "${customer_404_count[$key]}"
        fi
    done

    for key in "${!customer_other_non200_count[@]}"; do
        if [[ -z "${customer_200_count[$key]}" && -z "${customer_404_count[$key]}" ]]; then
            IFS='|' read -r hour customer_name client carrier_name attribute method <<< "$key"
            next_hour=$(date -d "@$(( $(date -d "$hour" +%s) + 3600 ))" "+%Y-%m-%d %H:00:00")
            printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15s %-15s %-15d %-30s %-25s\n" "$next_hour" "$customer_name" "$client" "$carrier_name" "$attribute" "$method" "0" "0" "${customer_other_non200_count[$key]}" "User not Supported" "${customer_other_non200_count[$key]}"
        fi
    done
}



# Aggregate logs by hour
aggregate_logs_by_hour

# Print the aggregated results
print_aggregated_results
