# SigNoz Setup for Unraid

> Deploy SigNoz observability platform on Unraid to monitor the MCP gateway stack.

## Overview

SigNoz provides unified logs, metrics, and traces with:

- **OpenTelemetry Collector** - Receives OTLP telemetry from apps
- **ClickHouse** - Single datastore for all signals
- **Query Service + Frontend** - Combined API backend + Web UI (port 3301)

## Prerequisites

- Unraid 6.12+
- 4GB+ RAM available for SigNoz
- Git installed on Unraid

## Quick Install (Official Method)

The simplest approach is to use SigNoz's official deployment:

```bash
ssh root@<unraid-ip>

# Clone SigNoz repo
cd /mnt/user/appdata
git clone -b main https://github.com/SigNoz/signoz.git --depth 1

# Change UI port from 8080 to 3301 (8080 may be used by agentgateway)
sed -i 's/8080:8080/3301:8080/' /mnt/user/appdata/signoz/deploy/docker/docker-compose.yaml

# Start SigNoz
cd /mnt/user/appdata/signoz/deploy/docker
docker compose up -d

# Wait for migrations and health checks (~2-3 minutes)
docker compose ps
```

## Verify Installation

```bash
# Check health
curl http://localhost:3301/api/v1/health
# Should return: {"status":"ok"}

# Access UI at http://<unraid-ip>:3301
```

## Connect MCP Gateway

### agentgateway

agentgateway has built-in OpenTelemetry support. Recreate with OTEL environment variables:

```bash
docker stop agentgateway
docker rm agentgateway

docker run -d \
  --name agentgateway \
  --network mcp-net \
  --restart unless-stopped \
  -p 8080:8080 \
  -p 15000:15000 \
  -e ADMIN_ADDR=0.0.0.0:15000 \
  -e OTEL_EXPORTER_OTLP_ENDPOINT=http://<unraid-ip>:4317 \
  -e OTEL_SERVICE_NAME=agentgateway \
  -e OTEL_TRACES_EXPORTER=otlp \
  -e OTEL_METRICS_EXPORTER=otlp \
  -v /mnt/user/appdata/agentgateway/config.yaml:/etc/agentgateway/config.yaml:ro \
  -v /mnt/user/appdata/agentgateway/jwks.json:/etc/agentgateway/jwks.json:ro \
  ghcr.io/agentgateway/agentgateway:latest
```

### Authelia

Authelia supports OpenTelemetry. Add to `configuration.yml`:

```yaml
telemetry:
  metrics:
    enabled: true
    address: "tcp://0.0.0.0:9959"
  tracing:
    enabled: true
    exporter: otlp
    endpoint: "<unraid-ip>:4317"
    insecure: true
    service_name: authelia
```

Then restart:

```bash
docker restart authelia
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SigNoz Stack                                      │
│                                                                              │
│   ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐      │
│   │    ZooKeeper     │    │   ClickHouse     │    │  OTEL Collector  │      │
│   │                  │◄───│                  │◄───│  :4317 (gRPC)    │      │
│   │                  │    │  (all signals)   │    │  :4318 (HTTP)    │      │
│   └──────────────────┘    └──────────────────┘    └────────▲─────────┘      │
│                                    │                        │                │
│                                    ▼                        │                │
│                           ┌──────────────────┐              │                │
│                           │  SigNoz Server   │              │                │
│                           │    :3301 (UI)    │              │                │
│                           └──────────────────┘              │                │
└─────────────────────────────────────────────────────────────┼────────────────┘
                                                              │
                                                    OTLP (traces/metrics)
                                                              │
┌─────────────────────────────────────────────────────────────┼────────────────┐
│                         MCP Gateway                         │                │
│   ┌────────────┐    ┌────────────┐    ┌────────────────────┴──┐             │
│   │ tailscale  │    │  authelia  │    │    agentgateway       │             │
│   │            │───▶│            │───▶│ OTEL_EXPORTER=:4317   │             │
│   └────────────┘    └────────────┘    └───────────────────────┘             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Endpoints

| Endpoint | URL | Description |
|----------|-----|-------------|
| SigNoz UI | http://<unraid-ip>:3301 | Web interface |
| OTLP gRPC | http://<unraid-ip>:4317 | For app telemetry |
| OTLP HTTP | http://<unraid-ip>:4318 | For app telemetry |
| Health | http://<unraid-ip>:3301/api/v1/health | Health check |

## Resource Usage

Expected resource usage on Unraid:

| Component | RAM | CPU | Storage |
|-----------|-----|-----|---------|
| ClickHouse | 1-2GB | Low | 10GB+/month |
| ZooKeeper | 256MB | Minimal | 100MB |
| SigNoz Server | 512MB | Low | Minimal |
| OTEL Collector | 256MB | Low | Minimal |
| **Total** | **~3-4GB** | Low | 10GB+/month |

## Retention

Default retention:

- **Logs**: 7 days
- **Traces**: 7 days
- **Metrics**: 30 days

Adjust in SigNoz UI: **Settings** > **General** > **Retention**

## Troubleshooting

### Port Conflict

If port 8080 is already in use:

```bash
# Check what's using 8080
docker ps | grep 8080

# Change SigNoz port
sed -i 's/8080:8080/3301:8080/' docker-compose.yaml
docker compose up -d
```

### No Data Appearing

```bash
# Check OTEL collector logs
docker logs signoz-otel-collector 2>&1 | tail -50

# Verify OTLP endpoint is reachable
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{}'
```

### Migrations Stuck

Schema migrations run on first start and can take 2-3 minutes:

```bash
# Check migration status
docker logs schema-migrator-sync 2>&1 | tail -20
```

## Update SigNoz

```bash
cd /mnt/user/appdata/signoz
git pull
cd deploy/docker
docker compose pull
docker compose up -d
```

## References

- [SigNoz Docker Installation](https://signoz.io/docs/install/docker/)
- [OpenTelemetry SDK Configuration](https://opentelemetry.io/docs/specs/otel/configuration/sdk-environment-variables/)
- [SigNoz GitHub](https://github.com/SigNoz/signoz)
