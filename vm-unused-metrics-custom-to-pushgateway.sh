#!/bin/bash

for cmd in jq curl; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "[ERROR] ${cmd} is not installed. Please install it to run this script."
    exit 1
  fi
done

# Maximum number of series to be returned by the TSDB status API.
# To configure this, set the flag -search.maxTSDBStatusTopNSeries in VictoriaMetrics.
# See the documentation: https://docs.victoriametrics.com/#resource-usage-limits
topN=10

# Single-node VictoriaMetrics:
vmselect_url="http://localhost:8428/prometheus/api/v1/status/tsdb?topN=${topN}"

# Cluster version of VictoriaMetrics:
# Replace <vmselect> with the actual vmselect address in your cluster.
# vmselect_url="<vmselect>:8481/select/0/prometheus/api/v1/status/tsdb?topN=${topN}"

# Job name for Prometheus
# Ensure that the job name is unique to avoid overwriting metrics.
job_name="victoria-metrics-statistics"

# Pushgateway URL
# Replace <your pushgateway> with the actual Pushgateway address.
pushgateway_url="<your pushgateway>/metrics/job/${job_name}"

# Actual timestamp
time_now=$(date +%s)

# Time limit for unused metrics
# Examples:
# 1 day -> 86400 seconds
# 7 days -> 604800 seconds
# 30 days -> 2592000 seconds
time_limit=604800

# Function to write the metric for unused metrics
write_vm_unused_metrics() {
  local metric_name="$1"
  local last_request="$2"
  local number_of_series="$3"
  cat <<EOF
vm_unused_metrics{last_request="${last_request}",metric_name="${metric_name}"} ${number_of_series}
EOF
}

# Query VictoriaMetrics TSDB Status API
curl -s "${vmselect_url}" | jq -r >temp.json

# Check if temp.json file is empty
if [ ! -s temp.json ]; then
  echo "[ERROR] Failed to query VictoriaMetrics API or got empty response from ${vmselect_url}."
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

# Add Prometheus headers
sed -i '1i\
# HELP vm_unused_metrics Number of metric series not queried\
# TYPE vm_unused_metrics gauge\
' vm_unused_metrics.prom

# Send metrics to Pushgateway with error checking
if ! curl -k --data-binary @vm_unused_metrics.prom "${pushgateway_url}"; then
  echo "[ERROR] Failed to send metrics to Pushgateway, check the url"
  rm -f temp.json metrics.csv vm_unused_metrics.prom
  exit 1
fi

# Cleanup
rm -f temp.json metrics.csv vm_unused_metrics.prom
