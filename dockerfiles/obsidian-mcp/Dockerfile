# syntax=docker/dockerfile:1

# Obsidian MCP Server with Supergateway
# Wraps cameronsjo/obsidian-mcp-tools (stdio) with HTTP transport for agentgateway
#
# Required env vars:
#   OBSIDIAN_API_KEY     - API key from Obsidian Local REST API plugin
#   OBSIDIAN_HOST        - Hostname of Obsidian container (default: obsidian)
#   OBSIDIAN_USE_HTTP    - Use HTTP instead of HTTPS (default: true for Docker)

FROM oven/bun:1 AS builder

WORKDIR /build

# Clone the repo and build the mcp-server package
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
    && git clone --depth 1 https://github.com/cameronsjo/obsidian-mcp-tools.git . \
    && bun install \
    && cd packages/mcp-server \
    && bun run build:linux \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Production image
FROM node:20-alpine

# Install supergateway
RUN npm install -g supergateway

# Create non-root user (use different UID since 1000 is taken in node:alpine)
RUN adduser -D -u 1001 mcp

WORKDIR /app

# Copy built binary from builder
COPY --from=builder /build/packages/mcp-server/dist/mcp-server-linux /app/obsidian-mcp-server
RUN chmod +x /app/obsidian-mcp-server

# Switch to non-root user
USER mcp

# Environment variables
ENV PORT=3000
ENV OBSIDIAN_HOST=obsidian
ENV OBSIDIAN_USE_HTTP=true
ENV NODE_TLS_REJECT_UNAUTHORIZED=0

# Expose HTTP port
EXPOSE 3000

# Health check - supergateway exposes /mcp for streamable HTTP
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q --spider http://localhost:${PORT}/mcp || exit 1

# Start supergateway wrapping the MCP server binary
# Uses streamable HTTP transport (compatible with agentgateway)
CMD ["sh", "-c", "supergateway --port ${PORT} --outputTransport streamableHttp --stdio '/app/obsidian-mcp-server'"]
