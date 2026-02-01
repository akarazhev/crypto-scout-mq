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

### Podman Compose Security
```yaml
services:
  crypto-scout-mq:
    security_opt:
      - no-new-privileges=true
    cap_drop:
      - ALL
    read_only: true
    tmpfs:
      - /tmp:rw,size=64m,mode=1777,nodev,nosuid
    init: true
    pids_limit: 1024
    security_opt:
      - seccomp=unconfined  # If needed for RabbitMQ
```

### Network Security
```yaml
# Only management UI exposed to localhost
ports:
  - "127.0.0.1:15672:15672"

# AMQP and Streams use container network only (no host exposure)
networks:
  - crypto-scout-bridge
```

### Resource Limits
```yaml
cpus: "1.0"
mem_limit: "256m"
mem_reservation: "128m"
ulimits:
  nofile:
    soft: 65536
    hard: 65536
```

## Secret Management

### Erlang Cookie
```bash
# Generate secure cookie
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
# Should show: secret/*
```

## Access Control

### Management UI
```ini
# rabbitmq.conf - Bind to localhost only
management.tcp.ip = 127.0.0.1
management.tcp.port = 15672
```

### User Security
```bash
# Create admin user (do not use default guest)
rabbitmqctl add_user admin 'strong_random_password'
rabbitmqctl set_user_tags admin administrator
rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"

# Delete guest user
rabbitmqctl delete_user guest

# Create service-specific user
rabbitmqctl add_user crypto_scout_mq 'service_password'
rabbitmqctl set_permissions -p / crypto_scout_mq ".*" ".*" ".*"
```

## Security Auditing

### Container Scanning
```bash
# Scan image for vulnerabilities
podman image inspect rabbitmq:4.1.4-management | jq '.[0].Config'

# Check running container security
podman inspect crypto-scout-mq | jq '.[0].HostConfig'
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
- [ ] Non-root user execution
- [ ] Read-only root filesystem
- [ ] tmpfs for writable areas
- [ ] No new privileges
- [ ] All capabilities dropped
- [ ] Resource limits configured
- [ ] PID limits set

### Network Level
- [ ] AMQP (5672) not exposed to host
- [ ] Streams (5552) not exposed to host
- [ ] Management UI on localhost only
- [ ] External network for service communication

### Application Level
- [ ] Guest user deleted
- [ ] Strong passwords for all users
- [ ] Principle of least privilege for permissions
- [ ] Secure Erlang cookie
- [ ] Definitions file loaded securely

### Host Level
- [ ] Secret files with 600 permissions
- [ ] Secrets not committed to git
- [ ] Data directory with appropriate permissions
- [ ] Regular security updates

## Security Incidents

### Unauthorized Access Detected
```bash
# Check current connections
podman exec crypto-scout-mq rabbitmqctl list_connections peer_host user

# Review recent logins
podman logs crypto-scout-mq | grep -i "auth\|login" | tail -50

# Rotate passwords immediately
podman exec crypto-scout-mq rabbitmqctl change_password user 'new_password'
```

### Container Compromise
```bash
# Stop container immediately
podman stop crypto-scout-mq

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
