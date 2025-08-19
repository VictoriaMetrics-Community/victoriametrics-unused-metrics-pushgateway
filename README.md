# Generate custom metrics about unused VictoriaMetrics series for Prometheus Pushgateway

## Motivation

In large observability environments, it is common for time series databases like VictoriaMetrics to accumulate a significant number of metrics that are no longer being queried or used. These unused metrics can consume storage, increase costs, and make troubleshooting more difficult.

This script was created to help you identify and expose custom metrics that are not being queried within a configurable time window. By exporting this information in Prometheus exposition format, you can:

- Visualize unused metrics in Grafana or other observability tools
- Automate cleanup or alerting for unused metrics
- Optimize storage and improve query performance in VictoriaMetrics

## How it works

- Queries the VictoriaMetrics TSDB status API to get the last request timestamp for each metric
- Filters metrics that have not been queried in the specified period
- Exports the result as a Prometheus metric (`vm_unused_metrics`)
- Pushes the result to a Prometheus Pushgateway for easy integration with your monitoring stack

## Usage

1. Configure the script variables as needed (VictoriaMetrics endpoint, Pushgateway URL, job name, time window, etc)
2. Run the script manually or schedule it as a CronJob
3. Visualize or alert on the `vm_unused_metrics` metric in your observability platform

## Requirements

- Bash
- curl
- jq
- VictoriaMetrics (Single-node or Cluster version)
- Pushgateway

## Configuration

- The script supports both single-node and cluster VictoriaMetrics deployments
- The number of metrics returned can be controlled with the `-search.maxTSDBStatusTopNSeries` flag in VictoriaMetrics (default: 10)
- The job name sent to Pushgateway is configurable via the `job_name` variable at the top of the script. This allows you to distinguish between different metric sources or jobs in your Prometheus setup.
- All configuration is done at the top of the script for easy customization

## Example output

```
vm_unused_metrics{last_request="never",metric_name="my_old_metric"} 42
vm_unused_metrics{last_request="2025-08-10T12:00:00",metric_name="another_unused_metric"} 5
```

## License

GPLv3
