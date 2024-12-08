#!/bin/bash

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
ORANGE='\033[0;33m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Global variables for statistics
LOG_FILE=""
VERBOSE_MODE=false
FASTEST_TIME=999999
FASTEST_DOMAIN=""
FASTEST_SERVER=""
TOTAL_QUERIES=0
TOTAL_TIME=0

# Function to download and extract domain list
download_and_extract_domain_list() {
local domain_list_file="/tmp/top-1m.csv"
local zip_file="/tmp/top-1m.csv.zip"

if [ -f "$domain_list_file" ]; then
if whiptail --yesno "Domain list file already exists. Do you want to download it again?" 10 60; then
rm -f "$domain_list_file"
else
return 0
fi
fi

echo "Downloading domain list..."
if ! curl -s -o "$zip_file" "https://s3-us-west-1.amazonaws.com/umbrella-static/top-1m.csv.zip"; then
whiptail --msgbox "Error downloading domain list." 10 60
return 1
fi

echo "Extracting domain list..."
if ! unzip -p "$zip_file" "top-1m.csv" > "$domain_list_file"; then
whiptail --msgbox "Error extracting domain list." 10 60
return 1
fi

rm "$zip_file"

if [ ! -s "$domain_list_file" ]; then
whiptail --msgbox "Error: Domain list file is empty or not found." 10 60
return 1
fi

echo "Domain list extracted successfully."
return 0
}

# Function to discover DNS servers
discover_dns_servers() {
grep '^nameserver' /etc/resolv.conf | awk '{print $2}'
}

# Function to query domains and measure performance
perform_queries() {
local domain_list="$1"
local query_count="$2"
shift 2
local servers=("$@")

echo "Performing DNS queries..."
for server in "${servers[@]}"; do
echo "Querying DNS server: $server"
local server_start_time=$(date +%s.%N)
local server_time=0
local server_queries=0
local fastest_time=999999
local fastest_domain=""

for ((i = 0; i < query_count; i++)); do
while IFS=, read -r rank domain; do
if [[ -n "$domain" ]]; then
domain=$(echo "$domain" | xargs)
break
fi
done < <(shuf -n 1 "$domain_list")

if [ -z "$domain" ]; then
echo "Error: Empty domain name found. Skipping query."
continue
fi

local dig_command="dig @${server} ${domain} +noall +stats +time=1 2>/dev/null"
if dig_output=$(eval "$dig_command"); then
local query_time=$(echo "$dig_output" | grep "Query time:" | awk '{print $4}')
if [ -z "$query_time" ]; then
query_time=0
fi

# Ensure query_time is a valid number before using bc
if [[ "$query_time" =~ ^[0-9]+$ ]]; then
TOTAL_TIME=$(echo "$TOTAL_TIME + $query_time" | bc)
server_time=$(echo "$server_time + $query_time" | bc)
if (( $(echo "$query_time < $fastest_time" | bc -l) )); then
fastest_time=$query_time
fastest_domain=$domain
fi
fi
((TOTAL_QUERIES++))
((server_queries++))

if $VERBOSE_MODE; then
local query_output="Domain being queried: ${YELLOW}$domain${NC}\n| Response: ${GREEN}success${NC} | Response time: ${ORANGE}${query_time}ms${NC}"
echo -e "$query_output"
echo -e "Domain being queried: $domain\n| Response: success | Response time: ${query_time}ms" >> "$LOG_FILE"
else
echo -ne "Queries completed: $((i + 1))/$query_count\r"
fi
else
if $VERBOSE_MODE; then
local query_output="Domain being queried: ${YELLOW}$domain${NC}\n| Response: ${RED}failure${NC} | Response time: ${ORANGE}N/A${NC}"
echo -e "$query_output"
echo -e "Domain being queried: $domain\n| Response: failure | Response time: N/A" >> "$LOG_FILE"
else
echo -ne "Queries completed: $((i + 1))/$query_count\r"
fi
fi
done

local server_end_time=$(date +%s.%N)
local server_total_time=$(echo "$server_end_time - $server_start_time" | bc)

# Log statistics for the server
local server_stats="Statistics:\n------------------------\nTotal execution time: ${server_total_time}s\nFastest server: $server\nFastest response time: ${fastest_time}ms\nFastest domain: $fastest_domain\n------------------------"
echo -e "$server_stats" >> "$LOG_FILE"
echo -e "$server_stats"
done
}

# Main Script
while true; do
download_and_extract_domain_list || exit 1

# Ask user about logfile
LOG_FILE=$(whiptail --inputbox "Enter log file path:" 10 60 "~/sialenost.log" 3>&1 1>&2 2>&3)
if [ -n "$LOG_FILE" ]; then
LOG_FILE=$(eval echo "$LOG_FILE")
touch "$LOG_FILE"

# Ask if the user wants to append or overwrite the log file
if whiptail --yesno "Do you want to append to the log file?" 10 60; then
: # Do nothing, append by default
else
> "$LOG_FILE" # Overwrite the log file
fi
fi

# Ask if verbose mode should be enabled
if whiptail --yesno "Enable verbose mode (detailed output for each query)?" 10 60; then
VERBOSE_MODE=true
fi

# Discover and select DNS servers
dns_servers=$(discover_dns_servers)
if [ -z "$dns_servers" ]; then
whiptail --msgbox "No DNS servers found. Exiting." 10 60
exit 1
fi

custom_dns=$(whiptail --inputbox "Enter custom DNS servers (comma-separated, or leave blank):" 10 60 3>&1 1>&2 2>&3)
if [ -n "$custom_dns" ]; then
all_dns=$(echo -e "$dns_servers\n$(echo "$custom_dns" | tr ',' '\n')" | sort -u)
else
all_dns=$(echo "$dns_servers" | sort -u)
fi

selected_dns=$(whiptail --checklist "Select DNS servers to query:" 20 60 10 $(echo "$all_dns" | awk '{print NR " " $1 " off"}') 3>&1 1>&2 2>&3)
if [ -z "$selected_dns" ]; then
whiptail --msgbox "No DNS servers selected. Exiting." 10 60
exit 1
fi

selected_dns_names=()
for index in $selected_dns; do
selected_dns_names+=($(echo "$all_dns" | awk "NR==$index"))
done

# Ask the user for query count
query_count=$(whiptail --inputbox "Enter the number of queries per server (1-1000):" 10 60 "10" 3>&1 1>&2 2>&3)
if ! [[ "$query_count" =~ ^[0-9]+$ ]] || [ "$query_count" -lt 1 ] || [ "$query_count" -gt 1000 ]; then
whiptail --msgbox "Invalid query count. Please enter a number between 1 and 1000." 10 60
exit 1
fi

# Perform queries
perform_queries "/tmp/top-1m.csv" "$query_count" "${selected_dns_names[@]}"

# Ask the user if they want to run the script again or quit
if ! whiptail --yesno "Do you want to run the script again?" 10 60; then
break
fi
done

# Thank you message
echo -e "\nThank you for using this script. I hope you like it and also find it useful. - Davidian-SK"
if [ -n "$LOG_FILE" ]; then
echo -e "\nThank you for using this script. I hope you like it and also find it useful. - Davidian-SK" >> "$LOG_FILE"
fi
