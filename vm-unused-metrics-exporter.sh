#!/bin/bash

# Verify dependencies
for package in jq curl; do
  if ! command -v "${package}" >/dev/null 2>&1; then
    echo "[ERROR] ${package} is not installed. Please install it to run this script."
    exit 1
  fi
done

# Show help message
show_help() {
  cat <<EOF

Usage: $0 --single-node <url> | --cluster-version <url> [options]

Options:
  --single-node <vm url>              VictoriaMetrics single-node base URL
  --cluster-version <vmselect url>    VictoriaMetrics cluster vmselect base URL
  --vminsert-url <vminsert url>       VictoriaMetrics cluster vminsert base URL (required with --cluster-version)
  --top <n>                           Number of top metrics to check (default: 10).
  --time-limit <h|d|m>                Time to consider a metric unused. Use formats like 12h (hours), 7d (days), 2m (months). Default: 7d
  --job <job_name>                    Job label for the exported metrics (default: victoriametrics-statistics)

  --help                              Show this help message and exit


Examples:
  $0 --single-node http://localhost:8428
  $0 --single-node http://localhost:8428 --time-limit 10d
  $0 --cluster-version https://vmselect:8480 --vminsert-url https://vminsert:8480 --top 100 --job myjob --time-limit 2m

EOF
}

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
  # Write the unused metric in the specified format
  cat <<EOF
vm_unused_metrics{job="${job}",last_request="${last_request}",metric_name="${metric_name}"} ${number_of_series}
EOF
}

# Script configuration
job="victoriametrics-statistics"
push_url=""
time_limit=604800 # 7 days in seconds (60s * 60m * 24h * 7d)
time_now=$(date +%s)
top=10
vm_url=""

# Argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
  # Parse command-line arguments
  --single-node)
    shift
    source_url="$1"
    # Validate source URL
    if [[ -z "$1" || "$1" =~ ^-- ]]; then
      echo "[ERROR] --single-node requires a non-empty argument."
      exit 1
    fi
    push_type="single-node"
    ;;
  --cluster-version)
    shift
    source_url="$1"
    # Validate source URL
    if [[ -z "$1" || "$1" =~ ^-- ]]; then
      echo "[ERROR] --cluster-version requires a non-empty argument."
      exit 1
    fi
    push_type="cluster-version"
    ;;
  --vminsert-url)
    shift
    vminsert_url="$1"
    # Validate vminsert URL
    if [[ -z "$1" || "$1" =~ ^-- ]]; then
      echo "[ERROR] --vminsert-url requires a non-empty argument."
      exit 1
    fi
    ;;
  --top)
    shift
    top="$1"
    ;;
  --time-limit)
    shift
    time_limit=$(parse_time_limit "$1")
    ;;
  --job)
    shift
    job="$1"
    ;;
  --help)
    show_help
    exit 0
    ;;
  *)
    echo "[ERROR] Unknown argument: $1"
    show_help
    exit 1
    ;;
  esac
  shift
done

# Validate URLs
case "${push_type}" in
single-node)
  # Build URLs for single-node mode
  vm_url="${source_url}/prometheus/api/v1/status/tsdb?topN=${top}"
  push_url="${source_url}/api/v1/import/prometheus"
  ;;
cluster-version)
  # Check if vminsert_url is provided
  if [[ -z "${vminsert_url}" ]]; then
    echo "[ERROR] --vminsert-url <vminsert url> is required when using --cluster-version."
    exit 1
  fi
  # Build URLs for cluster-version mode
  vm_url="${source_url}/select/0/prometheus/api/v1/status/tsdb?topN=${top}"
  push_url="${vminsert_url}/insert/0/prometheus/api/v1/import/prometheus"
  ;;
*)
  # Error handling for unspecified push type
  echo "[ERROR] You must specify --single-node <vm url> or --cluster-version <vminsert url>."
  exit 1
  ;;
esac

# Determine if curl should use -k for HTTPS URLs
curl_option=""
if [[ "${vm_url}" =~ ^https:// ]] || [[ "${push_url}" =~ ^https:// ]]; then
  curl_option="-k"
fi

# Query VictoriaMetrics TSDB Status API
curl -s ${curl_option} "${vm_url}" | jq -r >temp.json

# Check if temp.json file is empty
if [ ! -s temp.json ]; then
  echo "[ERROR] Failed to query VictoriaMetrics API or got empty response from ${vm_url}."
  rm -f temp.json
  exit 1
fi

# Filter metrics that have not been queried in the specified period
jq -r --argjson now "${time_now}" --argjson limit "${time_limit}" \
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
  echo "[ERROR] Failed to send metrics to ${push_url}, check the url"
  rm -f temp.json metrics.csv vm_unused_metrics.prom
  exit 1
fi

# Cleanup
rm -f temp.json metrics.csv vm_unused_metrics.prom
