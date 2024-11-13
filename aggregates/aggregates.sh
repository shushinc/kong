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
        echo "elango custome" "$hour"
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

# Print the aggregated results for each hour
print_aggregated_results() {
    printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15s %-15s %-15s\n" "Timestamp Interval" "Customer Name" "Client" "Carrier Name" "Attribute" "Method" "200 Status Count" "404 Status Count" "Other Non-200 Status"
    printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15s %-15s %-15s\n" "------------------" "-------------" "------" "------------" "---------" "------" "---------------" "---------------" "--------------------"

    # Loop through the associative array and print the table rows
    for key in "${!customer_200_count[@]}"; do
        # Split the key into its components
        IFS='|' read -r hour customer_name client carrier_name attribute method <<< "$key"
        
        # Calculate the next hour (end of the interval)
        # Convert `$hour` to seconds since the epoch, add 3600 seconds (1 hour), and convert back to desired format
        next_hour=$(date -d "@$(( $(date -d "$hour" +%s) + 3600 ))" "+%Y-%m-%d %H:00:00")
        # Print the aggregated data with only the next hour as the timestamp
        printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15d %-15d %-15d\n" "$next_hour" "$customer_name" "$client" "$carrier_name" "$attribute" "$method" "${customer_200_count[$key]}" "${customer_404_count[$key]:-0}" "${customer_other_non200_count[$key]:-0}"
    done

    # Check for any 404 or non-200 only entries
    for key in "${!customer_404_count[@]}"; do
        if [[ -z "${customer_200_count[$key]}" ]]; then
            # Split the key into its components
            IFS='|' read -r hour customer_name client carrier_name attribute method <<< "$key"
            
            next_hour=$(date -d "@$(( $(date -d "$hour" +%s) + 3600 ))" "+%Y-%m-%d %H:00:00")
            # Print the 404-only data with only the next hour as the timestamp
            printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15d %-15d %-15d\n" "$next_hour" "$customer_name" "$client" "$carrier_name" "$attribute" "$method" 0 "${customer_404_count[$key]}" "${customer_other_non200_count[$key]:-0}"
        fi
    done

    for key in "${!customer_other_non200_count[@]}"; do
        if [[ -z "${customer_200_count[$key]}" && -z "${customer_404_count[$key]}" ]]; then
            # Split the key into its components
            IFS='|' read -r hour customer_name client carrier_name attribute method <<< "$key"
            
            next_hour=$(date -d "@$(( $(date -d "$hour" +%s) + 3600 ))" "+%Y-%m-%d %H:00:00")
            # Print the non-200-only data with only the next hour as the timestamp
            printf "%-25s %-20s %-20s %-20s %-20s %-15s %-15d %-15d %-15d\n" "$next_hour" "$customer_name" "$client" "$carrier_name" "$attribute" "$method" 0 0 "${customer_other_non200_count[$key]}"
        fi
    done
}



# Aggregate logs by hour
aggregate_logs_by_hour

# Print the aggregated results
print_aggregated_results