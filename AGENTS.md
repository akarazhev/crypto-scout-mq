# AGENTS.md

This document provides guidelines for agentic coding contributors to the crypto-scout-mq RabbitMQ infrastructure module.

## Project Overview

RabbitMQ 4.1.4 infrastructure for the crypto-scout ecosystem, providing AMQP and Streams messaging capabilities. Deployed via Podman Compose with pre-provisioned topology, security hardening, and production-ready configuration.

## Repository Layout

```
crypto-scout-mq/
├── podman-compose.yml          # Container definition
├── rabbitmq/
│   ├── definitions.json        # Exchange/queue/stream definitions
│   ├── rabbitmq.conf          # Broker configuration
│   └── enabled_plugins        # Enabled plugins
├── secret/                     # Secrets directory (rabbitmq.env)
└── script/
    ├── network.sh             # Network creation helper
    ├── rmq_compose.sh         # Production runner
    └── rmq_user.sh            # User management helper
```

## Build, Deploy, and Manage Commands

### Infrastructure Setup

```bash
# Create Podman network
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
# Start RabbitMQ (recommended)
./script/rmq_compose.sh up -d

# Alternative: raw compose
podman compose -f podman-compose.yml up -d
```

### Manage

```bash
# Check status
./script/rmq_compose.sh status

# View logs
./script/rmq_compose.sh logs -f

# Restart
./script/rmq_compose.sh restart

# Stop (keep volumes)
./script/rmq_compose.sh down

# Stop and remove volumes (DESTRUCTIVE)
./script/rmq_compose.sh down --prune
```

### User Management

```bash
# Create admin user
./script/rmq_user.sh -u admin -p 'changeMeStrong!' -t administrator -y

# Create service user
./script/rmq_user.sh -u crypto_scout -p 'securePass!' -t none -y
```

### Health Checks

```bash
# Container health
podman exec crypto-scout-mq rabbitmq-diagnostics -q ping

# Virtual hosts
 curl http://localhost:15672/api/health/checks/virtual-hosts -u admin:password

# Management UI
open http://localhost:15672/
```

## Configuration Guidelines

### Security Best Practices

- **Erlang Cookie**: Generate strong random value, store in `secret/rabbitmq.env` with 600 permissions
- **User Management**: Create separate users for each service (client, collector, analyst)
- **Permissions**: Grant minimal required permissions per user
- **Guest User**: Delete default guest user in production
- **Network**: AMQP/Streams ports (5672, 5552) not exposed to host, only internal network

### Configuration Files

| File | Purpose | Format |
|------|---------|--------|
| `rabbitmq.conf` | Broker settings | INI-style |
| `definitions.json` | Topology (exchanges, queues, streams) | JSON |
| `enabled_plugins` | Plugin list | Plain text |
| `secret/rabbitmq.env` | Erlang cookie | KEY=value |

### Topology (definitions.json)

**Exchanges:**
- `crypto-scout-exchange` (direct) - Main exchange
- `dlx-exchange` (direct) - Dead letter exchange

**Streams:**
- `bybit-stream` - Bybit market data
- `crypto-scout-stream` - CMC and other data

**Queues:**
- `collector-queue` - Collector service queue
- `chatbot-queue` - Chatbot service queue
- `dlx-queue` - Dead letter queue

### Retention Policies

- **Streams**: max 2GB or 1 day, 100MB segments
- **DLX**: max 10k messages, 7 day TTL

## Code Style Guidelines

### Shell Scripts

**Script Header:**
```bash
#!/bin/bash
#
# MIT License
# Copyright (c) 2026 Andrey Karazhev
#
# Description of script purpose
#

set -euo pipefail
```

**Variable Naming:**
- Constants: `UPPER_SNAKE_CASE`
- Local variables: `lower_snake_case`
- Environment variables: `UPPER_SNAKE_CASE`

**Error Handling:**
```bash
# Check required commands
if ! command -v podman &> /dev/null; then
    echo "Error: podman not found" >&2
    exit 1
fi

# Check file exists
if [[ ! -f "$config_file" ]]; then
    echo "Error: Config not found: $config_file" >&2
    exit 1
fi
```

### Configuration Files

**rabbitmq.conf:**
- One setting per line
- Use spaces around `=`
- Group related settings
- Comment complex configurations

**definitions.json:**
- Pretty-printed JSON (2-space indent)
- Alphabetically sorted keys where logical
- Comments explaining non-obvious bindings

## Testing and Validation

### Pre-deployment Checks

```bash
# Validate compose file
podman compose -f podman-compose.yml config

# Check syntax
bash -n script/rmq_compose.sh
bash -n script/rmq_user.sh
```

### Post-deployment Validation

```bash
# Check container status
podman ps --filter name=crypto-scout-mq

# Verify streams exist
podman exec crypto-scout-mq rabbitmqctl list_streams

# Verify exchanges
podman exec crypto-scout-mq rabbitmqctl list_exchanges

# Test connectivity from services
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
podman-compose down --volumes
rm -rf ./data/rabbitmq
podman-compose up -d
```

### Stream Issues

```bash
# List stream consumers
podman exec crypto-scout-mq rabbitmqctl list_stream_consumers

# Check stream offsets
podman exec crypto-scout-mq rabbitmqctl list_stream_publishers
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
2. Review changelog for breaking changes
3. Test in staging environment
4. Deploy with rolling restart

## Key Dependencies

| Component | Version | Purpose |
|-----------|---------|---------|
| RabbitMQ | 4.1.4 | Message broker |
| Podman | Latest | Container runtime |
| Podman Compose | Latest | Container orchestration |

## License

MIT License - See `LICENSE` file.
