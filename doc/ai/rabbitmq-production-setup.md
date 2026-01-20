# RabbitMQ production setup for crypto-scout-mq

This document describes the production-ready RabbitMQ setup implemented in this repository, how it satisfies the
messaging and metrics requirements, and how to operate it.

## Overview

- Image: `rabbitmq:4.1.4-management`
- Plugins: `rabbitmq_management`, `rabbitmq_stream` (see `rabbitmq/enabled_plugins`)
- Config file: `rabbitmq/rabbitmq.conf`
- Definitions import: `rabbitmq/definitions.json` (queues, exchanges, bindings)
- Compose file: `podman-compose.yml`

## Networking and ports

- 5672: AMQP (container network only, not exposed to host)
- 5552: Streams (container network only, not exposed to host)
- 15672: Management UI (localhost only, `127.0.0.1`)

Note: AMQP and Streams ports are **not mapped to the host** — only containers on `crypto-scout-bridge` can reach them.
Management UI is bound to loopback for local-only access. Use an SSH tunnel or reverse proxy with TLS/auth for remote
access.

## Container networking

AMQP (5672) and Streams (5552) are **not exposed to the host** — only to containers on the `crypto-scout-bridge`
network. Other services connect via:

- AMQP: `crypto-scout-mq:5672` or `crypto_scout_mq:5672`
- Streams: `crypto-scout-mq:5552` or `crypto_scout_mq:5552`

The Streams advertised address is configured for inter-container connectivity:

- Host: `crypto_scout_mq`
- Port: `5552`

## Security and credentials

- Erlang cookie is supplied via `env_file`: `./secret/rabbitmq.env`.
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

- Streams:
    - `bybit-stream` (durable, `x-queue-type: stream`, `x-max-age=1D`, `x-max-length-bytes=2GB`,
      `x-stream-max-segment-size-bytes=100MB`).
    - `crypto-scout-stream` (durable, `x-queue-type: stream`, `x-max-age=1D`, `x-max-length-bytes=2GB`,
      `x-stream-max-segment-size-bytes=100MB`).
- Classic queues:
    - `collector-queue` (durable, TTL=6h, max length 2500, lazy mode, `x-overflow=reject-publish`, DLX routing).
    - `chatbot-queue` (durable, TTL=6h, max length 2500, lazy mode, `x-overflow=reject-publish`, DLX routing).
    - `dlx-queue` (durable, TTL=7d, lazy mode) — dead-letter queue for failed messages.
- Exchanges:
    - `crypto-scout-exchange` (direct) — main exchange for all routing.
    - `dlx-exchange` (direct) — dead-letter exchange.
- Bindings:
    - `crypto-scout-exchange` → `bybit-stream` with `routing_key=bybit`.
    - `crypto-scout-exchange` → `crypto-scout-stream` with `routing_key=crypto-scout`.
    - `crypto-scout-exchange` → `collector-queue` with `routing_key=collector`.
    - `crypto-scout-exchange` → `chatbot-queue` with `routing_key=chatbot`.
    - `dlx-exchange` → `dlx-queue` with `routing_key=dlx`.

## Policies

- Stream retention policy `stream-retention` applied to queues matching `.*-stream$`:
    - `queue-type=stream`
    - `max-length-bytes=2GB`
    - `max-age=1D`
    - `stream-max-segment-size-bytes=100MB`
      This enforces consistent retention for current and future streams, overriding queue-declared arguments when
      present.

## Stream retention policy

- **Configuration**: We combine time and size-based retention on all streams:
    - `x-max-age=1D`
    - `x-max-length-bytes=2GB`
    - `x-stream-max-segment-size-bytes=100MB`
- **Semantics**:
    - Retention is evaluated per segment. Deletions occur when a segment closes and a new one is created.
    - With both `x-max-age` and `x-max-length-bytes` set, a segment is removed when both conditions are met (AND), and
      at least one segment is always kept.
    - Operator policies can override queue-declared arguments; policy takes precedence.
- **References**:
    - RabbitMQ Streams: Data Retention (parameters and per-segment behavior)
      https://www.rabbitmq.com/docs/streams
    - CloudAMQP: Streams Limits & Configurations (argument names and AND semantics)
      https://www.cloudamqp.com/blog/rabbitmq-streams-and-replay-features-part-3-limits-and-configurations-for-streams-in-rabbitmq.html
    - Discussion on retention evaluation timing (segment rollover requirement)
      https://github.com/rabbitmq/rabbitmq-server/discussions/4384

## Configuration highlights (`rabbitmq/rabbitmq.conf`)

```
stream.listeners.tcp.1 = 0.0.0.0:5552
stream.advertised_host = crypto_scout_mq
stream.advertised_port = 5552
load_definitions = /etc/rabbitmq/definitions.json
management.tcp.ip = 0.0.0.0
management.rates_mode = basic
disk_free_limit.absolute = 2GB
vm_memory_high_watermark.relative = 0.6
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@crypto_scout_mq
```

## Compose highlights (`podman-compose.yml`)

- Image pinned to `4.1.4-management`.
- Ports: `15672` (localhost only); AMQP/Streams not exposed to host.
- Resource limits (small profile): `cpus: "2.0"`, `mem_limit: "1g"`, `mem_reservation: "512m"`.
- Healthcheck and `start_period` for readiness.
- Volumes for data, config, plugin list, and definitions.
- `env_file: ./secret/rabbitmq.env` provides `RABBITMQ_ERLANG_COOKIE`.
- Config mounts are read-only: `enabled_plugins`, `rabbitmq.conf`, `definitions.json`.
- Security hardening: `no-new-privileges`, `init`, `pids_limit: 1024`, tmpfs for `/tmp`, graceful `SIGTERM` and
  `stop_grace_period: 1m`.

## Readiness review

* __Image pinning__: `podman-compose.yml` uses `rabbitmq:4.1.4-management`.
* __Persistence__: Volume `./data/rabbitmq:/var/lib/rabbitmq` ensures durable data.
* __Health__: Healthcheck uses `rabbitmq-diagnostics -q ping` with `start_period: 30s`.
* __Ulimits__: `nofile` set to `65536` to prevent FD exhaustion.
* __Resource limits__: `cpus="2.0"`, `mem_limit="1g"`, `mem_reservation="512m"` (small production profile in compose).
* __Networking__: Port `15672` (localhost); AMQP/Streams container-network only.
* __Config__: `rabbitmq/rabbitmq.conf` enables Streams, loads definitions, pins `management.rates_mode=basic` and
  configures classic peer discovery with the local node (`rabbit@crypto_scout_mq`).
* __Plugins__: `rabbitmq/enabled_plugins` activates Management and Stream.
* __Definitions__: `rabbitmq/definitions.json` seeds vhost `/`, queues, exchanges, bindings.
* __Security__: No users embedded in definitions; create admins via `script/rmq_user.sh`. Erlang cookie provided via
  `./secret/rabbitmq.env`.
* __Security hardening__: Compose mounts are read-only, `no-new-privileges`, PID limit, tmpfs `/tmp`.
* __Backpressure__: Collector, chatbot, and analyst queues use lazy mode, `reject-publish` overflow, and DLX routing to
  protect the broker under load.
* __Dead-letter handling__: Failed messages route to `dlx-exchange` → `dlx-queue` (TTL=7d) for inspection/reprocessing.

## Operations

0) Ensure Podman network exists (compose uses an external network `crypto-scout-bridge`):

Recommended:

```bash
./script/network.sh
```

Alternative:

```bash
podman network create crypto-scout-bridge
```

1) Prepare a secret (see `secret/README.md`). Ensure `./secret/rabbitmq.env` defines the env var above.
2) Start: `podman compose -f podman-compose.yml up -d`
3) Verify health:
    - `podman ps` (healthy status)
    - UI: http://localhost:15672/
4) Verify resources:
    - Queues/streams/exchanges in Management UI → Queues/Exchanges tabs
    - Stream protocol open on `5552`