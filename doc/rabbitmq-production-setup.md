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
    - `crypto-bybit-stream` (durable, `x-queue-type: stream`, `x-max-age=7D`, `x-max-length-bytes=2GB`,
      `x-stream-max-segment-size-bytes=100MB`).
    - `metrics-bybit-stream` (durable, `x-queue-type: stream`, `x-max-age=7D`, `x-max-length-bytes=2GB`,
      `x-stream-max-segment-size-bytes=100MB`).
    - `metrics-cmc-stream` (durable, `x-queue-type: stream`, `x-max-age=7D`, `x-max-length-bytes=2GB`,
      `x-stream-max-segment-size-bytes=100MB`).
- Common ingress/messaging queue:
    - `crypto-scout-collector-queue` (durable, TTL=6h, max length 2500).
- Exchanges:
    - `crypto-exchange` (topic)
    - `collector-exchange` (topic)
    - `metrics-exchange` (topic)
- Bindings:
    - `crypto-exchange` → `crypto-bybit-stream` with `routing_key=crypto-bybit`.
    - `collector-exchange` → `crypto-scout-collector-queue` with `routing_key=crypto-scout-collector`.
    - `metrics-exchange` → `metrics-bybit-stream` with `routing_key=metrics-bybit`.
    - `metrics-exchange` → `metrics-cmc-stream` with `routing_key=metrics-cmc`.

## Stream retention policy

- **Configuration**: We combine time and size-based retention on all streams:
    - `x-max-age=7D`
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
stream.listeners.tcp.1 = 5552
load_definitions = /etc/rabbitmq/definitions.json
prometheus.tcp.port = 15692
prometheus.tcp.ip = 0.0.0.0
management.rates_mode = basic
deprecated_features.permit.management_metrics_collection = true
disk_free_limit.absolute = 2GB
vm_memory_high_watermark.relative = 0.6
```

## Compose highlights (`podman-compose.yml`)

- Image pinned to `4.1.4-management`.
- Ports: `5672`, `5552`, `15672`, `15692`.
- Healthcheck and `start_period` for readiness.
- Volumes for data, config, plugin list, and definitions.
- `env_file: ./secret/rabbitmq.env` provides `RABBITMQ_ERLANG_COOKIE`.

## Readiness review

* __Image pinning__: `podman-compose.yml` uses `rabbitmq:4.1.4-management`.
* __Persistence__: Volume `./data/rabbitmq:/var/lib/rabbitmq` ensures durable data.
* __Health__: Healthcheck uses `rabbitmq-diagnostics -q ping` with `start_period: 30s`.
* __Ulimits__: `nofile` set to `65536` to prevent FD exhaustion.
* __Networking__: Ports `5672`, `5552`, `15672`, `15692` published and listeners confirmed in logs.
* __Config__: `rabbitmq/rabbitmq.conf` enables Streams, Prometheus, loads definitions, pins
  `management.rates_mode=basic`, and permits `management_metrics_collection`.
* __Plugins__: `rabbitmq/enabled_plugins` activates Management, Prometheus, Stream, Consistent Hash.
* __Definitions__: `rabbitmq/definitions.json` seeds vhost `/`, queues, exchanges, bindings.
* __Security__: No default users created when loading definitions; create admins via `script/rmq_user.sh`. Erlang cookie
  provided via `./secret/rabbitmq.env`.
* __Observability__: Prometheus endpoint on `15692`.

## Operations

1) Prepare a secret (see `secret/README.md`). Ensure `./secret/rabbitmq.env` defines the env var above.
2) Start: `podman compose -f podman-compose.yml up -d`
3) Verify health:
    - `podman ps` (healthy status)
    - UI: http://localhost:15672/
    - Metrics: `curl -s http://localhost:15692/metrics | head`
4) Verify resources:
    - Queues/streams/exchanges in Management UI → Queues/Exchanges tabs
    - Stream protocol open on `5552`

## Log verification (2025-10-03)

* __Status__: Server startup complete; 6 plugins started (`rabbitmq_prometheus`, `rabbitmq_stream`,
  `rabbitmq_consistent_hash_exchange`, `rabbitmq_management`, `rabbitmq_management_agent`, `rabbitmq_web_dispatch`).
* __Ports/listeners__: AMQP 5672, Streams 5552, Management 15672, Prometheus 15692 listeners started successfully.
* __Definitions__: vhost `/`, 3 exchanges, 4 queues, and 4 bindings imported from `rabbitmq/definitions.json`.
* __Streams__: Writer for `crypto-bybit-stream` initialized; osiris log directory created under
  `/var/lib/rabbitmq/mnesia/.../stream/`.
* __Warnings observed__:
    - `management_metrics_collection` is deprecated. Impact: future minor releases may disable Management UI metrics by
      default.
    - Message store indices rebuilt from scratch (expected on first boot or clean data dir).
    - Classic peer discovery message about empty local node list (benign for single-node setups).
* __Errors__: none observed.

## Remediation implemented

* __Config__: Added `deprecated_features.permit.management_metrics_collection = true` to `rabbitmq/rabbitmq.conf` to
  preserve Management metrics behavior across future upgrades.
* __No further action needed__: Listeners bound, health expected, and definitions applied without errors.

## User provisioning

Create at least one admin user (definitions do not create users by design):

- __With helper script__ `script/rmq_user.sh`:

  ```bash
  ./script/rmq_user.sh -u admin -p 'changeMeStrong!' -t administrator -y
  ```

  Then log in to Management UI at http://localhost:15672/ with that user.

- __Alternative__ (direct in container):

  ```bash
  podman exec -it crypto-scout-mq rabbitmqctl add_user admin 'changeMeStrong!'
  podman exec -it crypto-scout-mq rabbitmqctl set_user_tags admin administrator
  podman exec -it crypto-scout-mq rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
  ```

## Notes and recommendations

- TLS: Consider enabling TLS for AMQP, Management, and Streams in production networks.
- RBAC: Create per-service users with least privilege (scoped permissions per vhost if you introduce more vhosts).
- Backups: Persist `/var/lib/rabbitmq` to reliable storage; snapshot or backup regularly.
- Observability: Scrape `15692/metrics` with Prometheus; build alerts on queue length, unroutable messages, and
  memory/disk watermarks.
- Clustering: This compose is single-node. For HA, deploy multiple nodes and set the same Erlang cookie across nodes,
  plus quorum queues/policies.

## Compliance with requirements

- Streams for crypto and metrics: `crypto-bybit-stream`, `metrics-bybit-stream`, `metrics-cmc-stream`.
- Common ingress/messaging queue: `crypto-scout-collector-queue`.
- Dead-letter queue removed: `metrics-dead-letter-queue` no longer used.
- Production readiness features: version pinning, persistent storage, health check, resource thresholds, metrics,
  secret-based credentials.

## Metrics streams migration (2025-10-04)

* __Objective__

  Replace classic metrics queues with streams and remove DLQ:
    - `metrics-bybit-queue` → `metrics-bybit-stream`
    - `metrics-cmc-queue` → `metrics-cmc-stream`
    - Remove `metrics-dead-letter-queue`

* __Rationale__

    - Streams provide append-only logs with replay, consumer offsets, and retention by size; better fit for analytics
      and time-series processing than transient queues with TTL/DLQ.
    - Unified approach: crypto and metrics both leverage Streams.

* __Implementation__

    - `rabbitmq/definitions.json`:
        - Added streams `metrics-bybit-stream`, `metrics-cmc-stream` with `x-queue-type=stream`,
          `x-max-length-bytes=2GB`, `x-stream-max-segment-size-bytes=100MB`.
        - Removed `metrics-dead-letter-queue`.
        - Updated bindings from `metrics-exchange` → `metrics-bybit-stream` (routing key `metrics-bybit`) and
          `metrics-exchange` → `metrics-cmc-stream` (routing key `metrics-cmc`).
    - `README.md` and this document updated to reflect the new topology.
    - No changes required to `podman-compose.yml`, `rabbitmq.conf`, or `enabled_plugins` (Streams already enabled, port
      `5552` exposed).

* __Producers and consumers__

    - Producers: continue publishing to `metrics-exchange` using existing routing keys `metrics-bybit` and
      `metrics-cmc`.
    - Consumers: prefer Stream protocol clients to benefit from offset management and replay capabilities. Coordinate
      consumer group names and starting offsets (e.g., from latest vs earliest) per service requirements.

* __Rollout and migration__ (for pre-existing environments)

    1. Create new streams and bindings (applied via updated `definitions.json`).
    2. Cut over consumers to read from the new streams.
    3. Optionally drain/inspect legacy `metrics-*-queue` contents.
    4. Delete legacy metrics queues and `metrics-dead-letter-queue`.

* __Verification__

    - Management UI → Queues: new items display as type "stream".
    - Publish a test message to `metrics-exchange` with `routing_key=metrics-bybit` and verify it appears in
      `metrics-bybit-stream`.
    - Confirm `:5552` stream listener is accepting connections.

## Documentation proposal and implementation (2025-10-03)

* __Proposed GitHub short description__

  Production-ready RabbitMQ service for the crypto-scout stack (AMQP + Streams + Prometheus), deployed via Podman
  Compose with a pre-provisioned messaging topology.

* __What was updated in `README.md`__

    - Added a concise project overview and the above short description.
    - Documented features grounded in this repo: image pinning to `rabbitmq:4.1.4-management`, enabled plugins from
      `rabbitmq/enabled_plugins`, pre-provisioned topology from `rabbitmq/definitions.json`, Prometheus metrics on
      `:15692/metrics`, healthcheck, raised file descriptors, persistent volume.
    - Repository layout, prerequisites (Podman + Compose plugin), quick start with secure Erlang cookie generation, and
      startup commands using `podman compose`.
    - Admin user provisioning using `script/rmq_user.sh` and equivalent manual commands.
    - Configuration highlights excerpted from `rabbitmq/rabbitmq.conf`.
    - Ports, persistence and backups guidance, security notes (secret handling, least-privilege users, TLS suggestion),
      and troubleshooting.

* __Grounding and sources__

    - Compose file: `podman-compose.yml`
    - Configuration: `rabbitmq/rabbitmq.conf`
    - Plugins: `rabbitmq/enabled_plugins`
    - Topology: `rabbitmq/definitions.json`
    - Secret guidance: `secret/README.md`, `secret/rabbitmq.env.example`
    - User provisioning script: `script/rmq_user.sh`

* __Notes__

    - The README avoids embedding credentials or user creation in `definitions.json` for security and rotation.
    - TLS enablement is recommended for production networks but is not configured in this repository (left to
      environment-specific deployment).
