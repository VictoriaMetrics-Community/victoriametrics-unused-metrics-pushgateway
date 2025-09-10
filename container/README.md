# VictoriaMetrics Unused Metrics Exporter (Container Version)

## Quick Start

## Building the Image

### Multi-architecture Build

```bash
docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 \
  -t your-registry/vm-unused-metrics-exporter:<your-tag> \
  --push .
```

### Single-architecture Build

```bash
docker build -t your-registry/vm-unused-metrics-exporter:<your-tag> .
```

## Running the Container

```bash
docker run --rm \
  -e VM_URL="<victoriametrics-url-or-vmselect-url>" \
  -e VM_PUSH_URL="<victoriametrics-url-or-vminsert-url>" \
  -e TOP="100" \
  -e JOB="victoriametrics-exporter" \
  -e TIME_LIMIT="30d" \
  your-registry/vm-unused-metrics-exporter:<your-tag>
```

## Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `VM_URL` | VictoriaMetrics URL (single-node or vmselect endpoint) | - | **Yes** |
| `VM_PUSH_URL` | VictoriaMetrics push URL (single-node or vminsert endpoint) | - | **Yes** |
| `TOP` | Number of top metrics to check | `10` | No |
| `JOB` | Job label for exported metrics | `victoriametrics-statistics` | No |
| `TIME_LIMIT` | Time to consider a metric unused (h/d/m) | `7d` | No |

## Kubernetes CronJob Example

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vm-unused-metrics-exporter
  namespace: <namespace>
spec:
  schedule: "*/60 * * * *"  # Every 60 minutes, set as needed
  jobTemplate:
    spec:
      template:
        metadata:
          labels: 
            app: vm-unused-metrics-exporter
        spec:
          containers:
          - name: vm-unused-metrics-exporter
            image: your-registry/vm-unused-metrics-exporter:latest
            env:
            - name: VM_URL
              value: "http://vmselect.acme.com"
            - name: VM_PUSH_URL
              value: "http://vminsert.acme.com"
            - name: TOP
              value: "100"
            - name: JOB
              value: "victoriametrics-exporter"
            - name: TIME_LIMIT
              value: "30d"
          restartPolicy: OnFailure
```

### Example metric output

```text
vm_unused_metrics{job="victoriametrics-statistics",last_request="never",metric_name="my_old_metric"} 42
vm_unused_metrics{job="victoriametrics-statistics",last_request="2025-08-10T12:00:00",metric_name="another_unused_metric"} 5
```
