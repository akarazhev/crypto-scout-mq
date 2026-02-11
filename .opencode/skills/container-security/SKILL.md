---
name: container-security
description: Container security hardening for RabbitMQ deployment with Podman
license: MIT
compatibility: opencode
metadata:
  container: podman
  security: hardening
  platform: linux
---

## What I Do

Provide security hardening guidance for RabbitMQ container deployment using Podman, following production security best practices.

## Security Model

### Defense in Depth
```
┌─────────────────────────────────────────────────────────┐
│                    Host System                          │
│  ┌─────────────────────────────────────────────────┐   │
│  │              Podman Container                    │   │
│  │  ┌─────────────────────────────────────────┐    │   │
│  │  │         Non-root User (10001)            │    │   │
│  │  │  ┌─────────────────────────────────┐    │    │   │
│  │  │  │       Read-only Root FS         │    │    │   │
│  │  │  │   ┌─────────────────────────┐   │    │    │   │
│  │  │  │   │   tmpfs /tmp (rw)       │   │    │    │   │
│  │  │  │   └─────────────────────────┘   │    │    │   │
│  │  │  └─────────────────────────────────┘    │    │   │
│  │  └─────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Security Configuration

### Podman Compose Security (from podman-compose.yml)
```yaml
services:
  crypto-scout-mq:
    image: rabbitmq:4.1.4-management
    security_opt:
      - no-new-privileges=true
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp:rw,size=64m,mode=1777,nodev,nosuid
    init: true
    pids_limit: 1024
    cpus: "1.0"
    mem_limit: "256m"
    mem_reservation: "128m"
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    restart: unless-stopped
    stop_signal: SIGTERM
    stop_grace_period: 1m
```

### Security Options Explained

| Option | Value | Purpose |
|--------|-------|---------|
| `no-new-privileges` | true | Prevents privilege escalation |
| `cap_drop` | ALL | Removes all Linux capabilities |
| `read_only` | true | Makes root filesystem read-only |
| `tmpfs` | /tmp | Writable temporary space |
| `init` | true | Uses init system for proper signal handling |
| `pids_limit` | 1024 | Limits process count |
| `cpus` | "1.0" | CPU limit |
| `mem_limit` | "256m" | Hard memory limit |
| `mem_reservation` | "128m" | Soft memory limit |
| `ulimits.nofile` | 65536 | File descriptor limit |

### Network Security
```yaml
# Only management UI exposed to localhost
ports:
  - "127.0.0.1:15672:15672"

# AMQP and Streams use container network only (no host exposure)
networks:
  - crypto-scout-bridge
```

### Volume Mounts (Read-only)
```yaml
volumes:
  - "./data/rabbitmq:/var/lib/rabbitmq"              # Data (read-write)
  - "./rabbitmq/enabled_plugins:/etc/rabbitmq/enabled_plugins:ro"
  - "./rabbitmq/rabbitmq.conf:/etc/rabbitmq/rabbitmq.conf:ro"
  - "./rabbitmq/definitions.json:/etc/rabbitmq/definitions.json:ro"
```

## Secret Management

### Erlang Cookie
```bash
# Generate secure cookie
cd crypto-scout-mq
COOKIE=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)
printf "RABBITMQ_ERLANG_COOKIE=%s\n" "$COOKIE" > secret/rabbitmq.env

# Secure permissions
chmod 600 secret/rabbitmq.env
```

### File Permissions Check
```bash
# Verify secret files
ls -la secret/
# Should show: -rw------- (600)

# Verify in .gitignore
grep secret/ .gitignore
# Should show: secret/*.env
```

## Access Control

### Management UI
```ini
# rabbitmq.conf - Management on all interfaces (restricted by container port binding)
management.tcp.ip = 0.0.0.0
management.tcp.port = 15672
```

The container port binding ensures it's only accessible via localhost:
```yaml
ports:
  - "127.0.0.1:15672:15672"  # Localhost only
```

### User Security
```bash
# Create admin user (do not use default guest)
./script/rmq_user.sh -u admin -p 'strong_random_password' -t administrator -y

# Or manually
rabbitmqctl add_user admin 'strong_random_password'
rabbitmqctl set_user_tags admin administrator
rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"

# Delete guest user
rabbitmqctl delete_user guest

# Create service-specific user
./script/rmq_user.sh -u crypto_scout_mq -p 'service_password' -t none -y
```

## Security Auditing

### Container Scanning
```bash
# Scan image for vulnerabilities
podman image inspect rabbitmq:4.1.4-management | jq '.[0].Config'

# Check running container security
podman inspect crypto-scout-mq | jq '.[0].HostConfig'

# Verify security options
podman inspect crypto-scout-mq | jq '.[0].HostConfig.SecurityOpt'
podman inspect crypto-scout-mq | jq '.[0].HostConfig.CapDrop'
podman inspect crypto-scout-mq | jq '.[0].HostConfig.ReadonlyRootfs'
```

### Log Monitoring
```bash
# Monitor authentication attempts
podman logs crypto-scout-mq | grep -i "auth\|login"

# Monitor connections
podman logs crypto-scout-mq | grep "accepting connection"

# Check for errors
podman logs crypto-scout-mq | grep -i "error\|warning"
```

## Hardening Checklist

### Container Level
- [x] Non-root user execution (RabbitMQ user inside container)
- [x] Read-only root filesystem
- [x] tmpfs for writable areas (/tmp)
- [x] No new privileges (no-new-privileges=true)
- [x] All capabilities dropped (cap_drop: ALL)
- [x] Resource limits configured (CPU, memory)
- [x] PID limits set (pids_limit: 1024)
- [x] Init system enabled for proper signal handling

### Network Level
- [x] AMQP (5672) not exposed to host
- [x] Streams (5552) not exposed to host
- [x] Management UI on localhost only (127.0.0.1:15672)
- [x] External network for service communication (crypto-scout-bridge)

### Application Level
- [x] Guest user deleted
- [x] Strong passwords for all users
- [x] Principle of least privilege for permissions
- [x] Secure Erlang cookie
- [x] Definitions file loaded securely (read-only mount)

### Host Level
- [x] Secret files with 600 permissions
- [x] Secrets not committed to git
- [x] Data directory with appropriate permissions
- [x] Regular security updates

## Security Incidents

### Unauthorized Access Detected
```bash
# Check current connections
podman exec crypto-scout-mq rabbitmqctl list_connections peer_host user

# Review recent logins
podman logs crypto-scout-mq | grep -i "auth\|login" | tail -50

# Rotate passwords immediately
./script/rmq_user.sh -u user -p 'new_password' -y
```

### Container Compromise
```bash
# Stop container immediately
./script/rmq_compose.sh down

# Do not remove - preserve for forensics
# Create new container with rotated secrets
# Review all user connections
```

## Compliance Notes

### Data Protection
- No PII stored in messages
- Encryption in transit (TLS recommended for production)
- No persistent sensitive data in container

### Audit Trail
- RabbitMQ logs connection attempts
- Management UI tracks user actions
- Container logs retained per policy

## When to Use Me

Use this skill when:
- Setting up production deployments
- Auditing security configuration
- Implementing security hardening
- Managing secrets and credentials
- Troubleshooting security incidents
- Reviewing access controls
- Ensuring compliance
