---
name: networking
description: Container networking configuration for RabbitMQ with Podman compose
description: Container networking configuration for RabbitMQ with Podman compose
license: MIT
compatibility: opencode
metadata:
  networking: container
  tool: podman
  domain: infrastructure
---

## What I Do

Provide networking configuration and troubleshooting guidance for RabbitMQ container deployment in the crypto-scout ecosystem.

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Host System                              │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              crypto-scout-bridge (Network)                │   │
│  │                                                           │   │
│  │   ┌──────────────┐         ┌─────────────────────┐       │   │
│  │   │ crypto-scout │◀───────▶│  crypto-scout-      │       │   │
│  │   │     -mq      │  5672   │    client           │       │   │
│  │   │              │  5552   │                     │       │   │
│  │   └──────┬───────┘         └─────────────────────┘       │   │
│  │          │                                               │   │
│  │          │  ┌─────────────────────┐                      │   │
│  │          └──▶  crypto-scout-      │                      │   │
│  │             │    collector        │                      │   │
│  │             └─────────────────────┘                      │   │
│  │                                                           │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│  External access: 127.0.0.1:15672 ──▶ Management UI             │
└─────────────────────────────────────────────────────────────────┘
```

## Port Configuration

### Internal Ports (Container Network Only)
| Port | Protocol | Purpose | Exposure |
|------|----------|---------|----------|
| 5672 | AMQP | Queue messaging | Container only |
| 5552 | Streams | Stream messaging | Container only |
| 4369 | EPMD | Erlang discovery | Container only |
| 25672 | Clustering | Inter-node communication | Container only |

### External Ports (Host Access)
| Port | Binding | Purpose |
|------|---------|---------|
| 15672 | 127.0.0.1:15672 | Management UI (localhost only) |

## Network Configuration

### External Network Creation
```bash
# Create once for all services
podman network create crypto-scout-bridge

# Verify creation
podman network ls
podman network inspect crypto-scout-bridge
```

### Compose Network Declaration
```yaml
networks:
  crypto-scout-bridge:
    name: crypto-scout-bridge
    external: true
```

### Service Network Attachment
```yaml
services:
  crypto-scout-mq:
    networks:
      - crypto-scout-bridge
```

## DNS and Discovery

### Container Hostnames
```yaml
services:
  crypto-scout-mq:
    hostname: crypto_scout_mq  # Underscores for Erlang
    container_name: crypto-scout-mq
```

### Service Discovery
Services connect using container names:
```java
// From crypto-scout-client
Environment.builder()
    .host("crypto-scout-mq")  // Container name resolves
    .port(5552)
    .build();
```

### Advertised Host (Streams)
```ini
# rabbitmq.conf
stream.advertised_host = crypto_scout_mq
stream.advertised_port = 5552
```

## Connectivity Testing

### From Host
```bash
# Management UI (localhost only)
curl http://127.0.0.1:15672

# AMQP/Streams NOT accessible from host
nc -zv localhost 5672  # Should fail
nc -zv localhost 5552  # Should fail
```

### From Other Containers
```bash
# Test from client container
podman exec crypto-scout-client nc -zv crypto-scout-mq 5672
podman exec crypto-scout-client nc -zv crypto-scout-mq 5552

# Test DNS resolution
podman exec crypto-scout-client nslookup crypto-scout-mq
```

### Diagnostics
```bash
# Container network info
podman inspect crypto-scout-mq | jq '.[0].NetworkSettings.Networks'

# IP address
podman inspect -f '{{.NetworkSettings.IPAddress}}' crypto-scout-mq

# Check listening ports
podman exec crypto-scout-mq rabbitmq-diagnostics -q listeners
```

## Troubleshooting

### Connection Refused
```bash
# Check if RabbitMQ is running
podman ps | grep crypto-scout-mq

# Check logs for startup errors
podman logs crypto-scout-mq

# Verify port binding
podman exec crypto-scout-mq netstat -tlnp
```

### DNS Resolution Failure
```bash
# Check network connectivity
podman exec crypto-scout-client ping crypto-scout-mq

# Verify network membership
podman inspect crypto-scout-mq | grep -A 10 "Networks"

# Restart with network
podman-compose down
podman-compose up -d
```

### Port Conflicts
```bash
# Check host port usage
lsof -i :15672
lsof -i :5672
lsof -i :5552

# Change management port if needed
# In podman-compose.yml:
ports:
  - "127.0.0.1:15673:15672"
```

### Firewall Issues
```bash
# Check firewall rules (host)
sudo iptables -L | grep 5672
sudo iptables -L | grep 5552

# Note: Container-to-container traffic uses internal networking
# and should not be affected by host firewall
```

## Advanced Configuration

### Custom Subnet
```bash
# Create network with specific subnet
podman network create \
  --subnet 10.88.10.0/24 \
  --gateway 10.88.10.1 \
  crypto-scout-bridge
```

### IPv6 Support
```yaml
# podman-compose.yml
networks:
  crypto-scout-bridge:
    enable_ipv6: true
    ipam:
      config:
        - subnet: 2001:db8::/64
```

### MTU Configuration
```yaml
# If experiencing network issues
networks:
  crypto-scout-bridge:
    driver_opts:
      mtu: 1400
```

## Security Considerations

### Network Isolation
```bash
# Verify no host exposure
podman port crypto-scout-mq
# Should only show: 127.0.0.1:15672 -> 15672

# Verify internal ports not exposed
podman inspect crypto-scout-mq | grep -A 20 PortBindings
```

### Inter-Service Communication
- Services should use container names for DNS resolution
- No hardcoded IP addresses
- Communication encrypted at application level if needed

## Performance Tuning

### Connection Limits
```yaml
ulimits:
  nofile:
    soft: 65536
    hard: 65536
```

### Network Mode
```yaml
# For host networking (not recommended for production)
network_mode: host
```

## Monitoring

### Network Metrics
```bash
# Container network I/O
podman stats crypto-scout-mq

# Connection count
podman exec crypto-scout-mq rabbitmqctl list_connections | wc -l

# Network interfaces in container
podman exec crypto-scout-mq ip addr
```

## When to Use Me

Use this skill when:
- Setting up container networking
- Troubleshooting connectivity issues
- Configuring service discovery
- Understanding port exposure
- Implementing network security
- Optimizing network performance
- Debugging DNS resolution
