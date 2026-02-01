# OpenCode Guide for crypto-scout-mq

OpenCode configuration for RabbitMQ infrastructure management in the crypto-scout ecosystem.

## Quick Start

```bash
# Use the admin agent for infrastructure tasks
@admin

# Use the monitor agent for monitoring and health checks
@monitor
```

## Agents

### @admin (Primary)
RabbitMQ infrastructure administrator.

**Use for:**
- Configuring RabbitMQ topology
- Managing users and permissions
- Starting/stopping services
- Troubleshooting connectivity
- Security configuration

**Capabilities:**
- Full tool access
- RabbitMQ 4.1.4 expertise
- Streams and AMQP protocols
- Podman container management

### @monitor (Subagent)
Monitoring and observability specialist.

**Use for:**
- Health checks
- Log analysis
- Performance monitoring
- Alert investigation
- Generating reports

**Limitations:**
- No configuration changes
- Read-only recommendations

## Skills

| Skill | Description | Use When |
|-------|-------------|----------|
| `rabbitmq-admin` | RabbitMQ administration | Managing topology, users, permissions |
| `container-security` | Security hardening | Securing deployments, auditing |
| `networking` | Container networking | Connectivity, DNS, troubleshooting |

## Common Workflows

### 1. Start Infrastructure

```
@admin
Start the crypto-scout-mq service and verify it's running correctly.
```

### 2. Create Users

```
@admin
Create an admin user and a service user for crypto-scout applications.
```

### 3. Check Health

```
@monitor
Check the health of the RabbitMQ service and report any issues.
```

### 4. Troubleshoot Connections

```
@admin
Applications can't connect to RabbitMQ. Help me troubleshoot.
```

## Configuration Files

| File | Purpose | Location |
|------|---------|----------|
| `definitions.json` | Topology (exchanges, queues, streams) | `rabbitmq/definitions.json` |
| `rabbitmq.conf` | Runtime configuration | `rabbitmq/rabbitmq.conf` |
| `enabled_plugins` | Plugin list | `rabbitmq/enabled_plugins` |
| `podman-compose.yml` | Container deployment | `podman-compose.yml` |

## Service Ports

| Port | Protocol | Access | Purpose |
|------|----------|--------|---------|
| 5672 | AMQP | Container only | Queue messaging |
| 5552 | Streams | Container only | Stream messaging |
| 15672 | HTTP | Localhost only | Management UI |

## Security Checklist

- [ ] Erlang cookie in `secret/rabbitmq.env` (600 permissions)
- [ ] Guest user deleted
- [ ] Strong passwords for all users
- [ ] Management UI on localhost only
- [ ] AMQP/Streams not exposed to host
- [ ] Container security options enabled
- [ ] Secrets not in git

## Quick Commands

```bash
# Start/stop
podman-compose up -d
podman-compose down

# Check status
podman ps
podman-compose ps

# View logs
podman logs -f crypto-scout-mq

# Health check
podman exec crypto-scout-mq rabbitmq-diagnostics -q ping

# Management UI
open http://localhost:15672
```

## Resources

- **RabbitMQ Version**: 4.1.4
- **Plugins**: management, stream, stream_management
- **Network**: crypto-scout-bridge
- **Documentation**: https://www.rabbitmq.com/documentation.html
