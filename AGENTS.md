# AGENTS.md

This document provides guidelines for agentic coding contributors to the crypto-scout-mq RabbitMQ infrastructure module.

## Project Overview

**crypto-scout-mq** is a RabbitMQ 4.1.4 infrastructure module for the crypto-scout ecosystem, providing AMQP and Streams messaging capabilities. Deployed via Podman Compose with pre-provisioned topology, security hardening, and production-ready configuration.

## MCP Server Configuration

This module uses the **Context7 MCP server** for enhanced code intelligence and documentation retrieval.

### Available MCP Tools

When working with this codebase, you can use the following MCP tools via the context7 server:

- **resolve-library-id**: Resolve a library name to its Context7 library ID
- **get-library-docs**: Retrieve up-to-date documentation for a library by its ID

### Configuration

The MCP server is configured in `.opencode/package.json`:

```json
{
  "mcp": {
    "context7": {
      "type": "remote",
      "url": "https://mcp.context7.com/mcp",
      "headers": {
        "CONTEXT7_API_KEY": "ctx7sk-4cec80b8-d947-4ff4-a29a-d00bea5a2fac"
      },
      "enabled": true
    }
  }
}
```

### Usage Guidelines

1. **RabbitMQ Configuration**: Use `resolve-library-id` for "rabbitmq" to get the latest configuration options, stream parameters, and AMQP protocol details.

2. **Podman Compose**: Retrieve container orchestration best practices and networking configuration guidance.

3. **Security Hardening**: Access RabbitMQ security documentation for user management, TLS configuration, and access control patterns.

4. **Stream Topology**: Get documentation on stream definitions, retention policies, and consumer group management.

## Repository Layout

```
crypto-scout-mq/
├── podman-compose.yml          # Container definition with security hardening
├── rabbitmq/
│   ├── definitions.json        # Exchange/queue/stream definitions and policies
│   ├── rabbitmq.conf           # Broker configuration (streams, management)
│   └── enabled_plugins         # Enabled plugins (management, stream)
├── script/
│   ├── network.sh              # Network creation helper (crypto-scout-bridge)
│   ├── rmq_compose.sh          # Production runner (up/down/logs/status/wait)
│   └── rmq_user.sh             # User management helper
├── secret/
│   ├── rabbitmq.env            # Erlang cookie (600 permissions, gitignored)
│   ├── rabbitmq.env.example    # Example cookie file
│   └── README.md               # Secrets documentation
├── .opencode/                  # OpenCode configuration
│   ├── agents/                 # Agent definitions
│   ├── skills/                 # Skill definitions
│   └── OPENCODE_GUIDE.md
├── README.md                   # Project documentation
└── LICENSE                     # MIT License
```

## Build, Deploy, and Manage Commands

### Infrastructure Setup

```bash
# Create Podman network (required before first start)
./script/network.sh
# OR
podman network create crypto-scout-bridge

# Prepare secrets
mkdir -p ./secret
cp ./secret/rabbitmq.env.example ./secret/rabbitmq.env
# Edit ./secret/rabbitmq.env with secure credentials
chmod 600 ./secret/rabbitmq.env
```

### Deploy

```bash
# Start RabbitMQ (recommended - waits for health)
./script/rmq_compose.sh up -d

# Alternative: raw compose (does not wait for health)
podman compose -f podman-compose.yml up -d
```

### Manage

```bash
# Check status and health
./script/rmq_compose.sh status

# View logs
./script/rmq_compose.sh logs -f

# Restart and wait for health
./script/rmq_compose.sh restart

# Stop (keep volumes)
./script/rmq_compose.sh down

# Stop and remove volumes (DESTRUCTIVE - erases broker state)
./script/rmq_compose.sh down --prune

# Wait for health explicitly
./script/rmq_compose.sh wait
```

### User Management

```bash
# Create admin user
./script/rmq_user.sh -u admin -p 'changeMeStrong!' -t administrator -y

# Create service user with full permissions
./script/rmq_user.sh -u crypto_scout -p 'securePass!' -y

# List existing users
./script/rmq_user.sh --list
```

### Health Checks

```bash
# Container health
podman exec crypto-scout-mq rabbitmq-diagnostics -q ping

# Virtual hosts API
curl http://localhost:15672/api/health/checks/virtual-hosts -u admin:password

# Management UI
open http://localhost:15672/
```

## Configuration Guidelines

### Security Best Practices

- **Erlang Cookie**: Generate strong random value (20-255 chars), store in `secret/rabbitmq.env` with 600 permissions
- **User Management**: Create separate users for each service (client, collector, analyst)
- **Permissions**: Grant minimal required permissions per user
- **Guest User**: Delete default guest user in production after creating admin
- **Network**: AMQP (5672) and Streams (5552) ports not exposed to host, only internal `crypto-scout-bridge` network
- **Management UI**: Bound to localhost only (`127.0.0.1:15672`)

### Configuration Files

| File | Purpose | Format |
|------|---------|--------|
| `rabbitmq.conf` | Broker settings (listeners, memory, disk limits) | INI-style key = value |
| `definitions.json` | Topology (exchanges, queues, streams, policies, bindings) | JSON |
| `enabled_plugins` | Plugin list | Erlang list syntax `[plugin1,plugin2].` |
| `secret/rabbitmq.env` | Erlang cookie environment variable | KEY=value |

### Topology (definitions.json)

**Exchanges:**
- `crypto-scout-exchange` (direct) - Main exchange for all message routing
- `dlx-exchange` (direct) - Dead letter exchange for failed messages

**Streams:**
- `bybit-stream` - Bybit market data (durable, x-queue-type: stream)
- `crypto-scout-stream` - CMC and other crypto-scout data (durable, x-queue-type: stream)

**Queues:**
- `collector-queue` - Collector service queue (lazy mode, max 2500, TTL 6h, DLX)
- `chatbot-queue` - Chatbot service queue (lazy mode, max 2500, TTL 6h, DLX)
- `dlx-queue` - Dead letter queue (lazy mode, max 10k, 7 day TTL)

**Bindings:**
- `crypto-scout-exchange` → `collector-queue` (routing key: `collector`)
- `crypto-scout-exchange` → `chatbot-queue` (routing key: `chatbot`)
- `crypto-scout-exchange` → `bybit-stream` (routing key: `bybit`)
- `crypto-scout-exchange` → `crypto-scout-stream` (routing key: `crypto-scout`)
- `dlx-exchange` → `dlx-queue` (routing key: `dlx`)

### Retention Policies

| Policy | Pattern | Settings |
|--------|---------|----------|
| `stream-retention` | `.*-stream$` | max 2GB or 1 day, 100MB segments |
| `dlx-retention` | `^dlx-queue$` | max 10k messages, 7 day TTL, reject-publish overflow |

## Code Style Guidelines

### Shell Scripts

**Script Header:**
```bash
#!/bin/bash
set -Eeuo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
```

**Logging Functions:**
```bash
log()    { printf "%s\n" "$*"; }
info()   { printf "[INFO] %s\n" "$*"; }
warn()   { printf "[WARN] %s\n" "$*" 1>&2; }
error()  { printf "[ERROR] %s\n" "$*" 1>&2; }
die()    { error "$*"; exit 1; }
```

**Variable Naming:**
- Constants: `UPPER_SNAKE_CASE` (e.g., `CONTAINER_DEFAULT`, `TIMEOUT`)
- Local variables: `lower_snake_case` (e.g., `compose_file`, `secret_file`)
- Environment variables: `UPPER_SNAKE_CASE`

**Error Handling:**
```bash
# Check required commands
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found"; }

# Trap errors and interrupts
trap 'error "An error occurred. See messages above."; exit 1' ERR
trap 'echo; warn "Interrupted by user."; exit 130' INT TERM
```

### Configuration Files

**rabbitmq.conf:**
- One setting per line
- Use spaces around `=`
- Group related settings (streams, management, limits)
- Comment complex configurations

**definitions.json:**
- Pretty-printed JSON (2-space indent)
- Alphabetically sorted keys within objects where logical
- Use descriptive names for exchanges, queues, and policies

**enabled_plugins:**
- Erlang list format: `[plugin1,plugin2].`
- No spaces after commas
- Trailing period required

## Testing and Validation

### Pre-deployment Checks

```bash
# Validate compose file
podman compose -f podman-compose.yml config

# Check script syntax
bash -n script/rmq_compose.sh
bash -n script/rmq_user.sh
bash -n script/network.sh
```

### Post-deployment Validation

```bash
# Check container status
podman ps --filter name=crypto-scout-mq

# Verify streams exist
podman exec crypto-scout-mq rabbitmqctl list_streams

# Verify exchanges
podman exec crypto-scout-mq rabbitmqctl list_exchanges

# Verify queues
podman exec crypto-scout-mq rabbitmqctl list_queues

# Test connectivity from other services
podman exec crypto-scout-client ping -c 3 crypto-scout-mq
```

## Troubleshooting

### Container Won't Start

```bash
# Check logs
podman logs crypto-scout-mq

# Verify network exists
podman network inspect crypto-scout-bridge

# Check ports not in use
lsof -i :15672
```

### Erlang Cookie Issues

```bash
# Cookie mismatch - clear data and restart
./script/rmq_compose.sh down --prune
rm -rf ./data/rabbitmq
./script/rmq_compose.sh up -d
```

### Stream Issues

```bash
# List stream consumers
podman exec crypto-scout-mq rabbitmqctl list_stream_consumers

# Check stream publishers
podman exec crypto-scout-mq rabbitmqctl list_stream_publishers

# Check stream offsets
podman exec crypto-scout-mq rabbitmqctl list_stream_tracking
```

## Maintenance

### Backup

```bash
# Backup definitions
podman exec crypto-scout-mq rabbitmqctl export_definitions /tmp/defs.json
podman cp crypto-scout-mq:/tmp/defs.json ./backup/definitions-$(date +%Y%m%d).json

# Backup data directory
tar czf rabbitmq-backup-$(date +%Y%m%d).tar.gz ./data/rabbitmq
```

### Updates

1. Update image version in `podman-compose.yml`
2. Review RabbitMQ changelog for breaking changes
3. Test in staging environment
4. Deploy with rolling restart: `./script/rmq_compose.sh restart`

## Key Dependencies

| Component | Version | Purpose |
|-----------|---------|---------|
| RabbitMQ | 4.1.4 | Message broker |
| Podman | Latest | Container runtime |
| Podman Compose | Latest | Container orchestration |

## License

MIT License - See `LICENSE` file.
