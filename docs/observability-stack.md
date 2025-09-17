# OpenTelemetry-Centric Observability Stack

This document describes the comprehensive observability stack deployed in our Kubernetes clusters, centered around OpenTelemetry (OTel) for unified telemetry collection and processing.

## Architecture Overview

The observability stack consists of the following components:

### Core Components

1. **OpenTelemetry Operator** (v0.135.0)
   - Manages OpenTelemetry Collector instances
   - Provides CRDs for collector configuration

2. **OpenTelemetry Collectors** (v0.97.0)
   - **Agent DaemonSet**: Collects logs, metrics, and traces from each node
   - **Gateway Deployment**: Central processing and routing of telemetry data

3. **Loki** (v3.3.0)
   - Log aggregation and storage
   - Receives logs via OpenTelemetry Collector

4. **Tempo** (v2.6.0)
   - Distributed tracing backend
   - Supports multiple trace formats (OTLP, Jaeger, Zipkin)

5. **Grafana** (v11.3.0)
   - Unified observability dashboard
   - Pre-configured data sources for Loki and Tempo
   - Cross-telemetry correlations (traces to logs, traces to metrics)

## Data Flow

```
Applications → OTel Collector (Agent) → OTel Collector (Gateway) → Backend Storage
                      ↓                            ↓                      ↓
               Node-level collection      Central processing      Loki (logs)
                                                                 Tempo (traces)
                                                                 Prometheus (metrics)
                            ↓
                       Grafana (visualization)
```

## Component Details

### OpenTelemetry Collector Agent (DaemonSet)
- **Purpose**: Collects telemetry data from each Kubernetes node
- **Collects**:
  - Container logs from `/var/log/pods`
  - Host metrics (CPU, memory, disk, network)
  - Kubelet metrics
  - Application traces and metrics via OTLP

### OpenTelemetry Collector Gateway (Deployment)
- **Purpose**: Central processing and routing hub
- **Features**:
  - Batch processing for efficiency
  - K8s metadata enrichment
  - Resource attribution
  - Load balancing across replicas
- **Exports to**:
  - Loki for logs
  - Tempo for traces
  - Prometheus for metrics (if available)

### Loki Configuration
- **Storage**: Local filesystem (suitable for development/local clusters)
- **Retention**: Configurable via `limits_config`
- **Integration**: Receives logs via OpenTelemetry Loki exporter
- **Features**:
  - LogQL for log queries
  - Trace correlation via trace IDs

### Tempo Configuration
- **Storage**: Local filesystem blocks
- **Protocols**: OTLP, Jaeger, Zipkin
- **Features**:
  - Multi-protocol ingestion
  - Query frontend for search performance
  - Service map generation

### Grafana Configuration
- **Authentication**: admin/admin123 (change for production)
- **Data Sources**: Pre-configured Loki, Tempo, and Prometheus
- **Features**:
  - Trace-to-logs correlation
  - Trace-to-metrics correlation
  - Service map visualization
  - Pre-built OpenTelemetry dashboard

## Deployment

The observability stack is deployed via FluxCD with proper dependency management:

```
cert-manager → opentelemetry-operator → loki, tempo → grafana → otel-collector
```

## Accessing Services

### Local Development (port-forward)

```bash
# Grafana UI
kubectl port-forward -n observability svc/grafana 3000:80

# Tempo API (for direct queries)
kubectl port-forward -n observability svc/tempo 3200:3200

# Loki API (for direct queries)
kubectl port-forward -n observability svc/loki 3100:3100
```

### URLs
- **Grafana**: http://localhost:3000 (admin/admin123)
- **Tempo**: http://localhost:3200
- **Loki**: http://localhost:3100

## Application Integration

### Sending Telemetry to the Stack

Applications can send telemetry data to the OpenTelemetry Collector Agent via:

#### OTLP (Recommended)
- **gRPC**: `http://otel-collector-agent-collector.observability.svc.cluster.local:4317`
- **HTTP**: `http://otel-collector-agent-collector.observability.svc.cluster.local:4318`

#### Legacy Protocols (via Gateway)
- **Jaeger gRPC**: `http://otel-collector-gateway-collector.observability.svc.cluster.local:14250`
- **Jaeger HTTP**: `http://otel-collector-gateway-collector.observability.svc.cluster.local:14268`
- **Zipkin**: `http://otel-collector-gateway-collector.observability.svc.cluster.local:9411`

### Environment Variables for Applications

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector-agent-collector.observability.svc.cluster.local:4317"
  - name: OTEL_SERVICE_NAME
    value: "your-service-name"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "service.version=1.0.0,deployment.environment=local"
```

## Monitoring the Monitoring Stack

The stack includes ServiceMonitors for Prometheus integration:
- Loki metrics: `/metrics` endpoint
- Tempo metrics: `/metrics` endpoint
- Grafana metrics: `/metrics` endpoint
- OTel Collector metrics: `8888/metrics` port

## Customization

### Storage Configuration
For production environments, update storage configurations in:
- `loki.yaml`: Switch from filesystem to object storage
- `tempo.yaml`: Configure object storage backend
- `grafana.yaml`: Use persistent volumes or external databases

### Scaling
- **Loki**: Scale replicas and configure distributed mode
- **Tempo**: Scale query-frontend and configure sharding
- **OTel Collector Gateway**: Increase replicas for higher throughput

### Security
- Change Grafana admin password
- Configure TLS for inter-service communication
- Set up RBAC policies
- Configure network policies

## Troubleshooting

### Common Issues

1. **OTel Collector not starting**: Check OpenTelemetry Operator logs
2. **Logs not appearing in Loki**: Verify file permissions on log directories
3. **Traces not appearing in Tempo**: Check OTel Collector configuration and endpoints
4. **Grafana data source connection issues**: Verify service names and ports

### Useful Commands

```bash
# Check OTel Collector status
kubectl get otelcol -n observability

# View collector logs
kubectl logs -n observability -l app.kubernetes.io/component=opentelemetry-collector -f

# Check component health
kubectl get pods -n observability

# View Grafana logs
kubectl logs -n observability deployment/grafana
```

## Next Steps

1. **Add Prometheus**: Integrate Prometheus for metrics storage and alerting
2. **Configure Alerting**: Set up Grafana alerts and notification channels
3. **Add Dashboards**: Import community dashboards for common services
4. **Set up SLOs**: Configure service level objectives and error budgets
5. **Production Hardening**: Implement security, scaling, and backup strategies

