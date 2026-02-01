---
name: rabbitmq-admin
description: RabbitMQ 4.1.4 administration including streams, AMQP, topology management, and troubleshooting
license: MIT
compatibility: opencode
metadata:
  messaging: rabbitmq
  version: "4.1.4"
  protocols: streams,amqp,management
---

## What I Do

Provide comprehensive guidance for administering RabbitMQ 4.1.4 in the crypto-scout ecosystem, including Streams, AMQP, topology configuration, and operational tasks.

## Core Concepts

### RabbitMQ Streams
High-throughput, append-only log messaging with:
- **Non-destructive reads**: Multiple consumers at different offsets
- **Offset tracking**: Per-consumer position management
- **Retention policies**: Time and size-based retention
- **Protocol**: Binary protocol on port 5552

### AMQP 0.9.1
Traditional message queuing with:
- **Queue-based**: FIFO message delivery
- **Acknowledgments**: Explicit delivery confirmation
- **Routing**: Exchange-based message routing
- **Protocol**: Binary protocol on port 5672

### Management UI
Web-based administration interface:
- **Port**: 15672 (localhost only in production)
- **Features**: Monitoring, configuration, user management
- **API**: RESTful API for automation

## Topology Reference

### Exchanges
| Exchange | Type | Purpose |
|----------|------|---------|
| `crypto-scout-exchange` | direct | Main message routing |
| `dlx-exchange` | direct | Dead letter handling |

### Streams
| Stream | Retention | Max Size | Purpose |
|--------|-----------|----------|---------|
| `bybit-stream` | 1 day | 2GB | Bybit market data |
| `crypto-scout-stream` | 1 day | 2GB | CMC/parser data |

### Queues
| Queue | Type | Arguments | Purpose |
|-------|------|-----------|---------|
| `collector-queue` | classic | lazy, TTL 6h, max 2500 | Control messages |
| `chatbot-queue` | classic | lazy, TTL 6h, max 2500 | Notifications |
| `dlx-queue` | classic | lazy, TTL 7d | Dead letters |

## Configuration Management

### definitions.json
Declarative topology configuration:
```json
{
  "vhosts": [{"name": "/"}],
  "exchanges": [...],
  "queues": [...],
  "bindings": [...],
  "policies": [...]
}
```

Loaded at startup via:
```ini
load_definitions = /etc/rabbitmq/definitions.json
```

### rabbitmq.conf
Key settings:
```ini
# Stream configuration
stream.listeners.tcp.1 = 0.0.0.0:5552
stream.advertised_host = crypto_scout_mq
stream.advertised_port = 5552

# Resource limits
disk_free_limit.absolute = 2GB
vm_memory_high_watermark.relative = 0.6

# Management
management.tcp.ip = 0.0.0.0
management.rates_mode = basic
```

### Environment Variables
```bash
RABBITMQ_ERLANG_COOKIE=secret_cookie
RABBITMQ_NODENAME=rabbit@crypto_scout_mq
```

## CLI Commands

### Node Operations
```bash
# Check status
rabbitmq-diagnostics -q ping
rabbitmq-diagnostics -q status

# Start/stop (inside container)
rabbitmqctl stop
rabbitmqctl start_app
```

### User Management
```bash
# List users
rabbitmqctl list_users

# Add user
rabbitmqctl add_user username 'password'
rabbitmqctl set_user_tags username administrator
rabbitmqctl set_permissions -p / username ".*" ".*" ".*"

# Change password
rabbitmqctl change_password username 'new_password'

# Delete user
rabbitmqctl delete_user username
```

### Queue Operations
```bash
# List queues
rabbitmqctl list_queues name messages consumers

# Purge queue
rabbitmqctl purge_queue queue_name

# Delete queue
rabbitmqctl delete_queue queue_name
```

### Stream Operations
```bash
# List streams
rabbitmqctl list_streams name retention_policy

# Stream consumer tracking
rabbitmqctl list_stream_consumers stream_name

# Stream publisher info
rabbitmqctl list_stream_publishers stream_name
```

## Monitoring Commands

### Health Checks
```bash
# Basic health
rabbitmq-diagnostics -q ping

# Listeners
rabbitmq-diagnostics -q listeners

# Alarms
rabbitmq-diagnostics -q alarms

# Memory
rabbitmq-diagnostics -q memory

# Overview
rabbitmq-diagnostics -q overview
```

### Connection Monitoring
```bash
# List connections
rabbitmqctl list_connections peer_host peer_port state user

# List channels
rabbitmqctl list_channels connection peer_pid user

# List consumers
rabbitmqctl list_consumers
```

## Security Best Practices

### Network Security
```bash
# Verify port exposure (container network only for AMQP/Streams)
podman inspect crypto-scout-mq | grep -A 5 "PortBindings"

# Management UI localhost only
management.tcp.ip = 127.0.0.1
```

### Access Control
```bash
# Principle of least privilege
rabbitmqctl set_permissions -p / user "^bybit-.*" "^bybit-.*" "^bybit-.*"

# Remove default user
rabbitmqctl delete_user guest
```

### Secret Management
```bash
# Secure Erlang cookie
tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48 > secret/rabbitmq.env
chmod 600 secret/rabbitmq.env
```

## Troubleshooting

### Connection Refused
```bash
# Check if running
podman ps | grep crypto-scout-mq

# Check logs
podman logs crypto-scout-mq

# Verify ports
podman exec crypto-scout-mq rabbitmq-diagnostics -q listeners
```

### Authentication Failed
```bash
# Check user exists
rabbitmqctl list_users | grep username

# Reset password
rabbitmqctl change_password username 'new_password'

# Check permissions
rabbitmqctl list_permissions -p /
```

### High Memory Usage
```bash
# Memory breakdown
rabbitmq-diagnostics -q memory

# Top queues by memory
rabbitmqctl list_queues name memory | sort -k2 -n | tail

# Connections
rabbitmqctl list_connections name peer_host memory_reduction
```

### Streams Not Working
```bash
# Check plugin
rabbitmq-plugins list | grep stream

# Verify stream listeners
rabbitmq-diagnostics -q listeners | grep 5552

# Check stream existence
rabbitmqctl list_streams
```

## When to Use Me

Use this skill when:
- Configuring RabbitMQ topology
- Managing users and permissions
- Monitoring service health
- Troubleshooting connectivity
- Understanding Streams vs AMQP
- Performing operational tasks
- Setting up security policies
