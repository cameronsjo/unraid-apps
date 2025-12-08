# Observability Stack Comparison

> Comparison of self-hosted observability solutions for MCP gateway monitoring.

## Quick Comparison

| Stack | Components | RAM | Complexity | Docker Socket | Best For |
|-------|------------|-----|------------|---------------|----------|
| **SigNoz** | All-in-one (ClickHouse) | 4-8GB | Low | Yes | Unified, simple setup |
| **Grafana LGTM** | Loki + Tempo + Mimir + Grafana | 4-8GB | Medium | Yes | Existing Grafana users |
| **Graylog** | Graylog + Elasticsearch + MongoDB | 6-12GB | High | Limited | Full-text log search |
| **GUS (Unraid)** | Grafana + InfluxDB + Loki | 2-4GB | Low | Yes | Unraid-specific |

## SigNoz

**Website:** https://signoz.io

### Overview

SigNoz is an open-source, OpenTelemetry-native observability platform that provides logs, metrics, and traces in a single application. Uses ClickHouse as its backend datastore.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         SigNoz Stack                            │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              OpenTelemetry Collector                     │   │
│  │  • docker_stats receiver (container metrics)            │   │
│  │  • filelog receiver (container logs)                    │   │
│  │  • otlp receiver (traces from apps)                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                    ClickHouse                            │   │
│  │            (single datastore for all signals)           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              SigNoz Query Service + UI                   │   │
│  │                    (port 8080)                           │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Pros

- **Single datastore** - ClickHouse handles logs, metrics, and traces
- **Native OpenTelemetry** - Built from the ground up for OTEL
- **Correlated signals** - Jump from trace to logs to metrics seamlessly
- **Lower operational overhead** - One thing to manage vs 4+ for LGTM
- **Cost efficient** - ClickHouse compression is excellent
- **20k+ GitHub stars** - Active community

### Cons

- **Less visualization flexibility** - Not as customizable as Grafana
- **Smaller ecosystem** - Fewer pre-built dashboards
- **ClickHouse learning curve** - If you need to tune it

### Requirements

- **OS:** Linux or macOS (Windows not supported)
- **RAM:** 4GB minimum allocated to Docker
- **Ports:** 8080 (UI), 4317 (OTLP gRPC), 4318 (OTLP HTTP)
- **Storage:** SSD recommended for ClickHouse

### Docker Socket Integration

SigNoz uses the OpenTelemetry `docker_stats` receiver:

```yaml
receivers:
  docker_stats:
    endpoint: unix:///var/run/docker.sock
    collection_interval: 10s
    container_labels_to_metric_labels:
      com.docker.compose.service: service_name
```

**Metrics collected:**
- `container.cpu.utilization`
- `container.memory.percent`
- `container.memory.usage.total`
- `container.network.io.usage.rx_bytes` / `tx_bytes`
- `container.blockio.io_service_bytes_recursive`

## Grafana LGTM Stack

**Website:** https://grafana.com

### Overview

The Grafana LGTM stack consists of:
- **L**oki - Log aggregation
- **G**rafana - Visualization
- **T**empo - Distributed tracing
- **M**imir - Metrics (Prometheus-compatible)

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       Grafana LGTM Stack                        │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │    Loki      │  │    Tempo     │  │    Mimir     │          │
│  │   (logs)     │  │  (traces)    │  │  (metrics)   │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│         │                 │                 │                   │
│         └─────────────────┼─────────────────┘                   │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                      Grafana                             │   │
│  │              (unified visualization)                     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              OpenTelemetry Collector                     │   │
│  │     (routes signals to appropriate backends)            │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Pros

- **Industry standard** - Grafana is the de-facto visualization tool
- **Massive ecosystem** - Thousands of dashboards, plugins
- **Flexible** - Mix and match components
- **LogQL/PromQL** - Powerful query languages
- **Alerting** - Built-in alerting with Grafana

### Cons

- **Multiple systems** - 4+ services to manage
- **Configuration overhead** - Each component has its own config
- **Signal correlation** - Requires manual linking (TraceID → logs)
- **Storage complexity** - Different backends for each signal

### Requirements

- **RAM:** 4-8GB minimum
- **Ports:** 3000 (Grafana), 3100 (Loki), 3200 (Tempo), 9009 (Mimir)
- **Storage:** Object storage recommended for production

### Docker Socket Integration

Uses Promtail or OTEL Collector with docker_stats receiver:

```yaml
# Promtail for logs
scrape_configs:
  - job_name: containers
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
```

## Graylog

**Website:** https://graylog.org

### Overview

Graylog is a centralized log management platform. Powerful full-text search via Elasticsearch, but heavyweight.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       Graylog Stack                             │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   MongoDB    │  │ Elasticsearch│  │   Graylog    │          │
│  │  (config)    │  │   (logs)     │  │  (server)    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

### Pros

- **Powerful search** - Full-text indexing via Elasticsearch
- **Stream processing** - Real-time log analysis
- **Alerting** - Built-in alerting system
- **GELF protocol** - Native structured logging

### Cons

- **Heavy** - 6-12GB RAM minimum
- **Complex** - Three services to manage
- **Elasticsearch overhead** - Resource hungry
- **No native tracing** - Logs only

### Requirements

- **RAM:** 6-12GB minimum
- **Ports:** 9000 (web), 12201 (GELF), 1514 (syslog)
- **Storage:** Fast storage for Elasticsearch

## GUS (Grafana-Unraid-Stack)

**GitHub:** https://github.com/testdasi/grafana-unraid-stack

### Overview

Unraid-specific all-in-one container with Grafana, InfluxDB, Telegraf, Loki, and Promtail.

### Pros

- **Unraid-optimized** - Built for the platform
- **Single container** - Everything bundled
- **Lightweight** - 2-4GB RAM
- **Pre-configured** - Works out of box

### Cons

- **No tracing** - Metrics and logs only
- **Less flexible** - Bundled components
- **Unraid-specific** - Not portable

## Recommendation Matrix

| Use Case | Recommended Stack |
|----------|-------------------|
| **MCP Gateway (your setup)** | SigNoz |
| **Already using Prometheus/Grafana** | Grafana LGTM |
| **Need powerful log search** | Graylog |
| **Unraid-only, minimal setup** | GUS |
| **Enterprise with compliance needs** | SigNoz or Graylog |
| **Learning/experimenting** | SigNoz (simplest) |

## Decision: SigNoz

For the MCP gateway stack, **SigNoz** is recommended because:

1. **Single deployment** - One docker-compose, one datastore
2. **Native OTEL** - agentgateway already emits OTEL traces
3. **Docker socket scraping** - Automatic container metrics
4. **Correlated signals** - Click from trace → logs seamlessly
5. **Lower RAM** - 4GB vs 8GB+ for full LGTM
6. **Simpler operations** - Less to maintain on Unraid

See [signoz-setup.md](./signoz-setup.md) for deployment guide.

## References

- [SigNoz Documentation](https://signoz.io/docs/)
- [SigNoz vs Grafana Comparison](https://signoz.io/product-comparison/signoz-vs-grafana/)
- [Grafana LGTM Stack](https://grafana.com/oss/)
- [Graylog Documentation](https://docs.graylog.org/)
- [GUS GitHub](https://github.com/testdasi/grafana-unraid-stack)
- [OpenTelemetry Docker Stats Receiver](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/dockerstatsreceiver)
