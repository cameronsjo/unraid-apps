# Obsidian MCP Server

Docker image wrapping [cameronsjo/obsidian-mcp-tools](https://github.com/cameronsjo/obsidian-mcp-tools) with [supergateway](https://github.com/supercorp-ai/supergateway) for HTTP transport.

## Architecture

```
agentgateway ──HTTP──▶ supergateway ──stdio──▶ obsidian-mcp-tools ──REST API──▶ Obsidian
                           :3000/mcp                                    :27123
```

## Prerequisites

- Obsidian running with [Local REST API](https://github.com/coddingtonbear/obsidian-local-rest-api) plugin
- API key from the plugin settings

## Features

- Semantic search via Smart Connections integration
- Templater template execution
- Full vault CRUD operations
- HTTP transport compatible with agentgateway

## Build

```bash
docker build -t ghcr.io/cameronsjo/obsidian-mcp:latest .
```

## Run

```bash
docker run -d \
  --name obsidian-mcp \
  --network mcp-net \
  --restart unless-stopped \
  -e OBSIDIAN_API_KEY=your-api-key-here \
  -e OBSIDIAN_HOST=obsidian \
  -e OBSIDIAN_USE_HTTP=true \
  ghcr.io/cameronsjo/obsidian-mcp:latest
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OBSIDIAN_API_KEY` | (required) | API key from Local REST API plugin |
| `OBSIDIAN_HOST` | `obsidian` | Hostname of Obsidian container |
| `OBSIDIAN_USE_HTTP` | `true` | Use HTTP (port 27123) vs HTTPS (port 27124) |
| `PORT` | `3000` | HTTP port for supergateway |

## agentgateway Config

```yaml
backends:
- mcp:
    targets:
    - name: obsidian
      mcp:
        host: http://obsidian-mcp:3000/mcp
```

## Tools Available

After deployment, tools are prefixed with `obsidian_`:

**Core Operations:**
- `obsidian_search` - Search notes
- `obsidian_read_note` - Read note content
- `obsidian_create_note` - Create new note
- `obsidian_update_note` - Update existing note
- `obsidian_list_notes` - List notes in directory

**Smart Connections:**
- `obsidian_semantic_search` - AI-powered semantic search

**Templater:**
- `obsidian_run_template` - Execute Templater templates
