# RabbitMQ production setup for crypto-scout-mq

This document describes the production-ready RabbitMQ setup implemented in this repository, how it satisfies the
messaging and metrics requirements, and how to operate it.

## Overview

- Image: `rabbitmq:4.1.4-management`
- Plugins: `rabbitmq_management`, `rabbitmq_prometheus`, `rabbitmq_stream`, `rabbitmq_consistent_hash_exchange` (see
  `rabbitmq/enabled_plugins`)
- Config file: `rabbitmq/rabbitmq.conf`
- Definitions import: `rabbitmq/definitions.json` (queues, exchanges, bindings)
- Compose file: `podman-compose.yml`

## Networking and ports

- 5672: AMQP
- 5552: Streams (required for `x-queue-type: stream`)
- 15672: Management UI
- 15692: Prometheus metrics (`/metrics`)

## Security and credentials

- Default admin and Erlang cookie are supplied via `env_file`: `./secrets/rabbitmq.env`.
    - `RABBITMQ_ERLANG_COOKIE`
- Users/permissions are not embedded in `definitions.json` to avoid leaking credentials and to simplify rotation.

## Reliability and resources

- Disk and memory thresholds moved to config:
    - `disk_free_limit.absolute = 2GB`
    - `vm_memory_high_watermark.relative = 0.6`
- File descriptors: `nofile` ulimit raised to `65536`.
- Graceful shutdown: `stop_grace_period: 1m`.
- Health check: `rabbitmq-diagnostics -q ping` with `start_period: 30s`.
- Persistent volume: `./data/rabbitmq:/var/lib/rabbitmq`.

## Streams and queues (from `rabbitmq/definitions.json`)

- Stream:
    - `crypto-bybit-stream` (durable, `x-queue-type: stream`, `x-max-length-bytes=2GB`,
      `x-stream-max-segment-size-bytes=100MB`).
- Common ingress/messaging queue:
    - `crypto-scout-collector-queue` (durable, TTL=6h, max length 2500).
- Metrics queues:
    - `metrics-bybit-queue` (durable, DLQ=`metrics-dead-letter-queue`, TTL=6h, max length 2500).
    - `metrics-cmc-queue` (durable, DLQ=`metrics-dead-letter-queue`, TTL=6h, max length 2500).
    - Dead-letter queue: `metrics-dead-letter-queue`.
- Exchanges:
    - `crypto-exchange` (topic)
    - `collector-exchange` (topic)
    - `metrics-exchange` (topic)
- Bindings:
    - `crypto-exchange` → `crypto-bybit-stream` with `routing_key=crypto.bybit`.
    - `collector-exchange` → `crypto-scout-collector-queue` with `routing_key=collector`.
    - `metrics-exchange` → `metrics-bybit-queue` with `routing_key=metrics.bybit`.
    - `metrics-exchange` → `metrics-cmc-queue` with `routing_key=metrics.cmc`.

## Configuration highlights (`rabbitmq/rabbitmq.conf`)

```
stream.listeners.tcp.1 = 5552
load_definitions = /etc/rabbitmq/definitions.json
prometheus.tcp.port = 15692
prometheus.tcp.ip = 0.0.0.0
disk_free_limit.absolute = 2GB
vm_memory_high_watermark.relative = 0.6
```

## Compose highlights (`podman-compose.yml`)

- Image pinned to `4.1.4-management`.
- Ports: `5672`, `5552`, `15672`, `15692`.
- Healthcheck and `start_period` for readiness.
- Volumes for data, config, plugin list, and definitions.
- `env_file: ./secrets/rabbitmq.env` provides `RABBITMQ_ERLANG_COOKIE`.

## Operations

1) Prepare secrets (see `secrets/README.md`). Ensure `./secrets/rabbitmq.env` defines the env var above.
2) Start: `podman compose -f podman-compose.yml up -d`
3) Verify health:
    - `podman ps` (healthy status)
    - UI: http://localhost:15672/
    - Metrics: `curl -s http://localhost:15692/metrics | head`
4) Verify resources:
    - Queues/streams/exchanges in Management UI → Queues/Exchanges tabs
    - Stream protocol open on `5552`

## Notes and recommendations

- TLS: Consider enabling TLS for AMQP, Management, and Streams in production networks.
- RBAC: Create per-service users with least privilege (scoped permissions per vhost if you introduce more vhosts).
- Backups: Persist `/var/lib/rabbitmq` to reliable storage; snapshot or backup regularly.
- Observability: Scrape `15692/metrics` with Prometheus; build alerts on queue length, unroutable messages, and
  memory/disk watermarks.
- Clustering: This compose is single-node. For HA, deploy multiple nodes and set the same Erlang cookie across nodes,
  plus quorum queues/policies.

## Compliance with requirements

- Stream for crypto data: `crypto-bybit-stream`.
- Common ingress/messaging queue: `crypto-scout-collector-queue`.
- Metrics queues: `metrics-bybit-queue`, `metrics-cmc-queue`.
- Production readiness features: version pinning, persistent storage, health check, resource thresholds, metrics,
  secrets-based credentials.
