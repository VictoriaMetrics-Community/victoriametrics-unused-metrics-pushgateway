#!/bin/bash

# Default configuration from environment variables
top="${VM_TOP:-10}"
job="${VM_JOB:-victoriametrics-statistics}"
time_limit="${TIME_LIMIT:-7d}"
vm_url="${VM_URL}"
vm_push_url="${VM_PUSH_URL}"

# Validate whether the required environment variable VM_URL has been set
if [[ -z "${vm_url}" ]]; then
  echo "[ERROR] VM_URL environment variable is required, please set it."
  exit 1
fi

# Validate whether the required environment variable VM_PUSH_URL has been set
if [[ -z "${vm_push_url}" ]]; then
  echo "[ERROR] VM_PUSH_URL environment variable is required, please set it."
  exit 1
fi

parse_time_limit() {
  local value="$1"
  if [[ "${value}" =~ ^([0-9]+)[hH]$ ]]; then
    echo $((BASH_REMATCH[1] * 3600))
  elif [[ "${value}" =~ ^([0-9]+)[dD]$ ]]; then
    echo $((BASH_REMATCH[1] * 86400))
  elif [[ "${value}" =~ ^([0-9]+)[mM]$ ]]; then
    echo $((BASH_REMATCH[1] * 2592000))
  else
    echo "[ERROR] Invalid time format. Use h|d|m (case-insensitive)."
    exit 1
  fi
}

# Function to write the metric for unused metrics
write_vm_unused_metrics() {
  local metric_name="$1"
  local last_request="$2"
  local number_of_series="$3"
  cat <<EOF
vm_unused_metrics{job="${job}",last_request="${last_request}",metric_name="${metric_name}"} ${number_of_series}
EOF
}

# Parse time limit
time_limit_seconds=$(parse_time_limit "${time_limit}")
time_now=$(date +%s)

# Determine if curl should use -k for HTTPS URLs
curl_option=""
if [[ "${vm_url}" =~ ^https:// ]] || [[ "${vm_push_url}" =~ ^https:// ]]; then
  curl_option="-k"
fi

# Build URL's for API and push
api_url="${vm_url}/prometheus/api/v1/status/tsdb?topN=${top}"
push_url="${vm_push_url}/api/v1/import/prometheus"

# Query VictoriaMetrics TSDB Status API
curl -s ${curl_option} "${api_url}" | jq -r >temp.json

# Check if temp.json file is empty
if [ ! -s temp.json ]; then
  echo "[ERROR] Failed to query VictoriaMetrics API or got empty response from ${api_url}"
  rm -f temp.json
  exit 1
fi

# Filter metrics that have not been queried in the specified period
jq -r --argjson now "${time_now}" --argjson limit "${time_limit_seconds}" \
  '.data.seriesCountByMetricName[]
    | select((.lastRequestTimestamp == 0) or (($now - .lastRequestTimestamp) > $limit))
    | "\(.name);\(.value);\(.requestsCount);\(.lastRequestTimestamp)"' temp.json >metrics.csv

# If no metrics match the filter, exit gracefully
if [ ! -s metrics.csv ]; then
  echo "No metrics found that are unused in the specified period."
  rm -f temp.json metrics.csv
  exit 0
fi

# Generate Prometheus metrics file
while IFS=';' read -r metric_name number_of_series requests_count timestamp; do
  [[ -z "${metric_name}" ]] && continue
  if [[ "${requests_count}" == "0" ]]; then
    last_request_date="never"
  else
    last_request_date=$(date -d @"${timestamp}" +"%Y-%m-%dT%H:%M:%S")
  fi
  write_vm_unused_metrics "${metric_name}" "${last_request_date}" "${number_of_series}"
done <metrics.csv >vm_unused_metrics.prom

# Add Prometheus headers to the metrics file
sed -i '1i\
# HELP vm_unused_metrics Number of metric series not queried for a long time\
# TYPE vm_unused_metrics gauge\
' vm_unused_metrics.prom

# Send metrics to VictoriaMetrics with error checking
if ! curl ${curl_option} --data-binary @vm_unused_metrics.prom "${push_url}"; then
  echo "[ERROR] Failed to send metrics to ${push_url}"
  rm -f temp.json metrics.csv vm_unused_metrics.prom
  exit 1
fi

# Cleanup
rm -f temp.json metrics.csv vm_unused_metrics.prom

# Success message
echo "[OK] Successfully exported unused metrics to VictoriaMetrics"