
# VictoriaMetrics Unused Metrics Exporter

## Motivation

In large observability environments, it is common for time series databases like VictoriaMetrics to accumulate a significant number of metrics that are no longer being queried or used. These unused metrics can consume storage, increase costs, and make troubleshooting more difficult.

This script helps you identify and expose metrics in VictoriaMetrics (single-node or cluster) that have not been queried within a configurable time window. It exports this information in Prometheus exposition format and pushes the result directly to VictoriaMetrics ingestion endpoints.

With this script, you can:

- Visualize unused metrics in Grafana or other observability tools
- Automate cleanup or alerting for unused metrics
- Optimize storage and improve query performance in VictoriaMetrics

## How it works

- Queries the VictoriaMetrics TSDB status API to get the last request timestamp for each metric
- Filters metrics that have not been queried in the specified period (configurable with `--time-limit`)
- Exports the result as a Prometheus metric (`vm_unused_metrics`)
- Pushes the result directly to the VictoriaMetrics ingestion endpoint (single-node or cluster)

## CLI version

You can run the script for both single-node and cluster VictoriaMetrics deployments. All configuration is done via command-line arguments:

```bash
./vm-unused-metrics-export.sh --single-node <vm url> [options]
./vm-unused-metrics-export.sh --cluster-version <vmselect url> --vminsert-url <vminsert url> [options]
```

**Options:**

- `--single-node <vm url>`: VictoriaMetrics single-node base URL (**required** for single-node mode)
- `--cluster-version <vmselect url>`: VictoriaMetrics cluster vmselect base URL (**required** for cluster mode)
- `--vminsert-url <vminsert url>`: VictoriaMetrics cluster vminsert base URL (**required** with --cluster-version)
- `--top <n>`: Number of top metrics to check (default: 10). To increase this limit, you must also set the `-search.maxTSDBStatusTopNSeries` flag in your VictoriaMetrics configuration (see below). *(optional)*
- `--time-limit <h|d|m>`: Time window to consider a metric unused. Use formats like `12h` (hours), `7d` (days), `2m` (months). Default: 7d. *(optional)*
- `--job <job_name>`: Job label for the exported metrics (default: victoriametrics-statistics). *(optional)*
- `--help`: Show help message and exit

**Examples:**

```sh
# Single-node, default time window (7 days)
./vm-unused-metrics-export.sh --single-node http://localhost:8428

# Single-node, custom time window (10 days)
./vm-unused-metrics-export.sh --single-node http://localhost:8428 --time-limit 10d

# Cluster, custom time window (2 months)
./vm-unused-metrics-export.sh --cluster-version https://vmselect:8480 --vminsert-url https://vminsert:8480 --top 100 --job myjob --time-limit 2m
```

### Requirements

- Bash
- curl
- jq
- VictoriaMetrics (Single-node or Cluster version)

### Configuration

- The script supports both single-node and cluster VictoriaMetrics deployments.
- The number of metrics returned is controlled by the `--top` argument, but also depends on the VictoriaMetrics flag `-search.maxTSDBStatusTopNSeries`. See the [official documentation](https://docs.victoriametrics.com/#resource-usage-limits).
  - **Example:** To allow up to 1000 metrics, add the following to your VictoriaMetrics startup:

    ```text
        -search.maxTSDBStatusTopNSeries=1000
    ```

- The job name is configurable via the `--job` argument.
- The time window for unused metrics is set with `--time-limit` (supports h/d/m, e.g., 12h, 7d, 2m).
- All configuration is done via command-line arguments for flexibility.

### Example metric output

```text
vm_unused_metrics{job="victoriametrics-statistics",last_request="never",metric_name="my_old_metric"} 42
vm_unused_metrics{job="victoriametrics-statistics",last_request="2025-08-10T12:00:00",metric_name="another_unused_metric"} 5
```

### Notes

- For cluster mode, both `--cluster-version` (vmselect) and `--vminsert-url` (vminsert) must be provided.
- The script pushes metrics directly to VictoriaMetrics ingestion endpoints.

## Container version

See the [container/README.md](container/README.md) for details.

## License

GPLv3
