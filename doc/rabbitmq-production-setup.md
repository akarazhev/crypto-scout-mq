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
    - `bybit-ta-stream` (durable, `x-queue-type: stream`, `x-max-age=1D`, `x-max-length-bytes=2GB`,
      `x-stream-max-segment-size-bytes=100MB`).
    - `crypto-scout-stream` (durable, `x-queue-type: stream`, `x-max-age=1D`, `x-max-length-bytes=2GB`,
      `x-stream-max-segment-size-bytes=100MB`).
- Classic queues:
    - `collector-queue` (durable, TTL=6h, max length 2500, lazy mode, `x-overflow=reject-publish`, DLX routing).
    - `chatbot-queue` (durable, TTL=6h, max length 2500, lazy mode, `x-overflow=reject-publish`, DLX routing).
    - `analyst-queue` (durable, TTL=6h, max length 2500, lazy mode, `x-overflow=reject-publish`, DLX routing).
    - `dlx-queue` (durable, TTL=7d, lazy mode) — dead-letter queue for failed messages.
- Exchanges:
    - `crypto-scout-exchange` (direct) — main exchange for all routing.
    - `dlx-exchange` (direct) — dead-letter exchange.
- Bindings:
    - `crypto-scout-exchange` → `bybit-stream` with `routing_key=bybit`.
    - `crypto-scout-exchange` → `bybit-ta-stream` with `routing_key=bybit-ta`.
    - `crypto-scout-exchange` → `crypto-scout-stream` with `routing_key=crypto-scout`.
    - `crypto-scout-exchange` → `collector-queue` with `routing_key=collector`.
    - `crypto-scout-exchange` → `chatbot-queue` with `routing_key=chatbot`.
    - `crypto-scout-exchange` → `analyst-queue` with `routing_key=analyst`.
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

## Log verification (2025-10-03)

* __Status__: Server startup complete; plugins started (`rabbitmq_stream`, `rabbitmq_management`,
  `rabbitmq_management_agent`, `rabbitmq_web_dispatch`).
* __Ports/listeners__: AMQP 5672, Streams 5552, Management 15672 listeners started successfully.
* __Definitions__: vhost `/`, exchanges, queues, and bindings imported from `rabbitmq/definitions.json`.
* __Streams__: Writer initialized; osiris log directory created under `/var/lib/rabbitmq/mnesia/.../stream/`.
* __Warnings observed__:
    - Message store indices rebuilt from scratch (expected on first boot or clean data dir).
    - Classic peer discovery message about empty local node list (benign for single-node setups).
* __Errors__: none observed.

## Remediation implemented

* __No further action needed__: Listeners bound, health expected, and definitions applied without errors.

## User provisioning

Definitions do not include users by design (credentials created separately after first run). Create an administrator:

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

- Delete the default 'guest' user:
  ```bash
  podman exec -it crypto-scout-mq rabbitmqctl delete_user guest
  ```

## Notes and recommendations

- TLS: Consider enabling TLS for AMQP, Management, and Streams in production networks.
- RBAC: Create per-service users with least privilege (scoped permissions per vhost if you introduce more vhosts).
- Backups: Persist `/var/lib/rabbitmq` to reliable storage; snapshot or backup regularly.
- Observability: Monitor via Management UI; consider enabling Prometheus plugin if metrics scraping is needed.
- Clustering: This compose is single-node. For HA, deploy multiple nodes and set the same Erlang cookie across nodes,
  plus quorum queues/policies.

## Compliance with requirements

- Streams: `bybit-stream`, `bybit-ta-stream`, `crypto-scout-stream`.
- Classic queues: `collector-queue`, `chatbot-queue`, `analyst-queue`, `dlx-queue`.
- Exchanges: `crypto-scout-exchange` (main), `dlx-exchange` (dead-letter).
- Bindings and routing keys: `bybit`, `bybit-ta`, `crypto-scout`, `collector`, `chatbot`, `analyst`, `dlx`.
- Dead-letter infrastructure: `dlx-exchange` → `dlx-queue` for failed message handling.
- User provisioning: create users after first run via `script/rmq_user.sh`.
- Production readiness features: version pinning, persistent storage, health check, resource thresholds, secret-based
  credentials.

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

  Production-ready RabbitMQ service for the crypto-scout stack (AMQP + Streams), deployed via Podman Compose with a
  pre-provisioned messaging topology.

* __What was updated in `README.md`__

    - Added a concise project overview and the above short description.
    - Documented features grounded in this repo: image pinning to `rabbitmq:4.1.4-management`, enabled plugins from
      `rabbitmq/enabled_plugins`, pre-provisioned topology from `rabbitmq/definitions.json`, healthcheck, raised file
      descriptors, persistent volume.
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

## Bybit TA stream addition (2025-10-20)

* __Objective__

  Introduce a new technical-analysis stream `crypto-bybit-ta-stream` based on the existing `crypto-bybit-stream` to
  carry analyzed Bybit data. Keep retention and stream semantics consistent with other streams.

* __Rationale__

    - Separation of concerns: raw vs analyzed data on distinct streams simplifies consumer responsibilities and replay.
    - Stream benefits: append-only log, consumer offsets, replay capabilities for analytics workloads.
    - Consistency: reuse existing retention policy `stream-retention` and queue arguments for uniform operations.

* __Implementation__

    - `rabbitmq/definitions.json`:
        - Added stream queue `crypto-bybit-ta-stream` with `x-queue-type=stream`,
          `x-max-length-bytes=2GB`, `x-max-age=1D`, `x-stream-max-segment-size-bytes=100MB`.
        - Added binding from `crypto-exchange` → `crypto-bybit-ta-stream` with `routing_key=crypto-bybit-ta`.
    - No changes required to `podman-compose.yml` or `rabbitmq/rabbitmq.conf` (Streams already enabled; port `5552`
      exposed;
      advertised host/port statically configured).

* __Producers and consumers__

    - Producers: publish analyzed events to `crypto-exchange` with routing key `crypto-bybit-ta`.
    - Consumers: use Streams protocol on `:5552`, choose consumer group names and starting offsets (earliest/latest) per
      service.

* __Verification__

    1. Management UI → Exchanges → `crypto-exchange` → Publish message with routing key `crypto-bybit-ta`; confirm it
       appears in stream `crypto-bybit-ta-stream`.
    2. Management UI → Queues: verify `crypto-bybit-ta-stream` shows type "stream".
    3. Ensure Streams listener is active on `5552` and advertised address is correct (see `rabbitmq/rabbitmq.conf`).

## Chatbot queue addition (2025-10-20)

* __Objective__

  Introduce a new classic queue `chatbot-queue` based on `collector-queue` to deliver
  analyzed crypto data to a chatbot processor.

* __Rationale__

    - Worker-style consumption: classic queue suits task-driven consumers with at-least-once delivery and acks.
    - Operational parity: reuse collector queue settings (TTL/backlog limits/lazy/overflow) to bound backlog and protect
      the broker.

* __Implementation__

    - `rabbitmq/definitions.json`:
        - Added queue `chatbot-queue` (durable, `x-message-ttl=21600000` (6h), `x-max-length=2500`, `x-queue-mode=lazy`,
          `x-overflow=reject-publish`).
        - Added binding from `crypto-scout-exchange` → `chatbot-queue` with `routing_key=chatbot`.
    - No changes required to `podman-compose.yml` or `rabbitmq/rabbitmq.conf`.

* __Producers and consumers__

    - Producers: publish analyzed messages to `crypto-scout-exchange` with routing key `chatbot`.
    - Consumers: consume from `chatbot-queue` over AMQP; set an appropriate `prefetch` and ack explicitly.

* __Verification__

    1. Management UI → Exchanges → `crypto-scout-exchange` → Publish message with routing key `chatbot`;
       confirm it appears in `chatbot-queue`.
    2. Ensure queue properties show TTL=6h, max length 2500, mode "lazy".

* __Rollout__

    - To apply updated definitions in a running environment, restart the broker so it reloads `definitions.json`:
      ```bash
      ./script/rmq_compose.sh restart
      ```
    - Alternatively, import definitions via the Management HTTP API.

## Topology update (2025-10-24)

- **Objective**

  Align names and routing for crypto data ingestion, parser outputs, and interservice communication; add an analyst
  queue for chatbot processing.

- **Changes (rename map and additions)**

    - Streams:
        - `crypto-bybit-stream` → `bybit-crypto-stream`
        - `crypto-bybit-ta-stream` → `bybit-ta-crypto-stream`
        - `metrics-bybit-stream` → `bybit-parser-stream`
        - `metrics-cmc-stream` → `cmc-parser-stream`
    - Exchanges:
        - `metrics-exchange` → `parser-exchange`
        - `crypto-exchange` → `bybit-exchange`
        - Defined: `crypto-scout-exchange` (direct)
    - Classic queues:
        - Defined: `analyst-queue` (durable; TTL=6h; max length 2500; lazy; `x-overflow=reject-publish`)
    - Routing keys:
        - `crypto-bybit` → `bybit`
        - `crypto-bybit-ta` → `bybit-ta`
        - `metrics-bybit` → `bybit-parser`
        - `metrics-cmc` → `cmc-parser`
        - Defined: `collector`, `chatbot`, `analyst`

- **Implementation**

    - Updated `rabbitmq/definitions.json`:
        - Renamed streams and exchanges as above; added `analyst-queue` queue with hardened arguments.
        - Updated bindings to point to new exchanges and destinations with new routing keys.
    - No changes required to `podman-compose.yml`, `rabbitmq/rabbitmq.conf`, or `rabbitmq/enabled_plugins`.

- **Producers and consumers**

    - Bybit producers: publish to `bybit-exchange` with `routing_key=bybit` or `bybit-ta`.
    - Parser producers: publish to `parser-exchange` with `routing_key=bybit-parser` or `cmc-parser`.
    - Consumers:
        - Streams: `bybit-crypto-stream`, `bybit-ta-crypto-stream`, `bybit-parser-stream`, `cmc-parser-stream` via
          Streams protocol on `:5552`.
        - Classic: `collector-queue`, `chatbot-queue`, `analyst-queue` over AMQP (`prefetch` + explicit acks
          recommended).

- **Migration and rollout**

    1. Apply updated definitions (restart to reload `definitions.json` or import via HTTP API).
    2. Retarget producers to new exchanges and routing keys.
    3. Point consumers at the new streams/queues; for streams choose group/offset strategy (earliest/latest).
    4. Optionally drain/verify legacy resources before removal.
    5. Remove unused legacy resources after cutover.

- **Verification**

    - Management UI → Exchanges:
        - Publish to `bybit-exchange` with `bybit`/`bybit-ta`; verify messages in `bybit-crypto-stream`/
          `bybit-ta-crypto-stream`.
        - Publish to `parser-exchange` with `bybit-parser`/`cmc-parser`; verify in corresponding streams.
        - Publish to `crypto-scout-exchange` with `collector`/`chatbot`/`analyst`; verify messages land in respective
          queues.
    - Ensure Streams listener on `:5552` is reachable; advertised address correct in `rabbitmq/rabbitmq.conf`.

## Log verification (2025-10-24)

- **Status**: Server startup complete; plugins started. AMQP/Streams/Management listeners active. Definitions loaded
  successfully.
- **Errors**: none observed.
- **Warnings observed** and dispositions:
    - **Erlang cookie override**: expected with `RABBITMQ_ERLANG_COOKIE` supplied via `./secret/rabbitmq.env`.
    - **Peer discovery (single node)**: previous benign warning about local node list was addressed by explicitly
      listing the node.
    - **Message store index rebuild**: expected on first boot/clean data dir.

## Logging remediation (2025-10-24)

- **Objective**: Remove non-actionable warnings at startup.
- **Changes** (`rabbitmq/rabbitmq.conf`):
    - Add single-node peer discovery:
        - `cluster_formation.peer_discovery_backend = classic_config`
        - `cluster_formation.classic_config.nodes.1 = rabbit@crypto_scout_mq`
- **Rationale**:
    - Explicit classic peer discovery node suppresses a benign warning on first boot in single-node setups.
- **Verification**:
    1. Restart the service: `./script/rmq_compose.sh restart`.
    2. Check logs: `./script/rmq_compose.sh logs -n 200` — no peer discovery node list warning; listeners active;
       definitions applied.
- **Impact**:
    - Keep `management.rates_mode=basic` for UI responsiveness.

## Configuration review (2025-10-25)

- **[verdict]** Ready for production in a single-node topology.
- **[reviewed files]** `podman-compose.yml`, `rabbitmq/rabbitmq.conf`, `rabbitmq/definitions.json`,
  `rabbitmq/enabled_plugins`, `secret/README.md`, `secret/rabbitmq.env.example`.
- **[strengths]** Version pinning (`rabbitmq:4.1.4-management`), persistent storage, healthcheck with start period,
  file descriptors `nofile=65536`, graceful shutdown, Streams retention policy, read-only config mounts,
  `no-new-privileges`, PID limit, and tmpfs for `/tmp`.
- **[security model]** No users embedded in definitions. Provision admin/service users post-deploy via
  `script/rmq_user.sh` and delete `guest`.

- **[recommendations]** Optional hardening and operational enhancements:
    - Restrict Management exposure if not needed publicly:
        - Map to loopback in `podman-compose.yml`: `127.0.0.1:15672:15672`.
        - Or set `management.tcp.ip = 127.0.0.1` and front with a reverse proxy (TLS + auth) for remote access.
    - Resource constraints: add CPU/memory limits in `podman-compose.yml` per host capacity and SLOs.
    - Extra hardening: consider `cap_drop: ["ALL"]` (works with non-privileged ports), and `read_only: true` with
      explicit writable mounts for `/var/lib/rabbitmq` and tmpfs for `/tmp` (test thoroughly before enabling).
    - TLS: enable TLS for AMQP, Streams, and Management when crossing untrusted networks.
    - Backups: snapshot `./data/rabbitmq` regularly and perform restore drills.
    - Streams external clients: if accessed from outside the host, set `stream.advertised_host/port` to routable values
      in `rabbitmq/rabbitmq.conf` and ensure firewall/NAT rules are in place.
    - Watermarks: adjust `disk_free_limit.absolute` and `vm_memory_high_watermark.relative` to match the host's storage
      and workload profile.

- **[recheck]** No blocking issues found. The deployment meets production-readiness goals for a single-node broker with
  pre-provisioned topology.

## Solution review (2025-10-27)

- **[verdict]** Ready for production (single-node) with AMQP + Streams.
- **[what changed]** Documentation now includes the external Podman network prerequisite and expanded quick start/ops.
- **[validated]**
    - Image pinning: `rabbitmq:4.1.4-management` in `podman-compose.yml`.
    - Plugins: `rabbitmq_management`, `rabbitmq_stream` in `rabbitmq/enabled_plugins`.
    - Exchanges are `direct` in `rabbitmq/definitions.json` (`crypto-scout-exchange`, `dlx-exchange`).
    - Streams and classic queues configured with retention/TTL/backpressure as listed above.
    - Streams external access documented via `stream.advertised_host/port` in `rabbitmq/rabbitmq.conf`.
- **[recommendations]** Optional hardening and ops enhancements to consider per environment:
    - Network exposure: keep Management (15672) on loopback; use SSH tunnel or reverse proxy with TLS/auth if remote
      access is required.
    - TLS: enable TLS for AMQP/Streams/Management on untrusted networks.
    - Container hardening: evaluate `cap_drop: ["ALL"]` and `read_only: true` with explicit writable mounts (
      `/var/lib/rabbitmq`, tmpfs `/tmp`). Test thoroughly.
    - Resource tuning: adjust `cpus`, `mem_limit`, `disk_free_limit.absolute`, and `vm_memory_high_watermark.relative`
      to match workload and host capacity.
    - Backups: schedule regular snapshots of `./data/rabbitmq` and perform restore drills.
    - Logs: keep `management.rates_mode=basic` for UI responsiveness. Configure host/container log rotation as needed.

No additional code changes are required for production readiness at this time.

## Topology update and Prometheus removal (2025-12-10)

- **Objective**

  Simplify the messaging topology to a unified exchange model, add dead-letter infrastructure, and remove Prometheus
  plugin/configuration.

- **Changes**

    - **Topology consolidation**:
        - Unified to single main exchange: `crypto-scout-exchange` (direct).
        - Streams renamed: `bybit-stream`, `bybit-ta-stream`, `crypto-scout-stream`.
        - Removed exchanges: `bybit-exchange`, `parser-exchange`.
        - Removed streams: `bybit-crypto-stream`, `bybit-ta-crypto-stream`, `bybit-parser-stream`, `cmc-parser-stream`.
    - **Dead-letter infrastructure**:
        - Added `dlx-exchange` (direct) and `dlx-queue` (TTL=7d, lazy mode).
        - Classic queues (`collector-queue`, `chatbot-queue`, `analyst-queue`) now route to DLX on rejection/expiry.
    - **User provisioning**:
        - Users not embedded in definitions; create after first run via `script/rmq_user.sh`.
    - **Prometheus removal**:
        - Removed `rabbitmq_prometheus` from `rabbitmq/enabled_plugins`.
        - Removed `prometheus.tcp.port` and `prometheus.tcp.ip` from `rabbitmq/rabbitmq.conf`.
        - Removed port `15692` mapping from `podman-compose.yml`.

- **Routing keys**

    - `bybit` → `bybit-stream`
    - `bybit-ta` → `bybit-ta-stream`
    - `crypto-scout` → `crypto-scout-stream`
    - `collector` → `collector-queue`
    - `chatbot` → `chatbot-queue`
    - `analyst` → `analyst-queue`
    - `dlx` → `dlx-queue`

- **Producers and consumers**

    - All producers publish to `crypto-scout-exchange` with appropriate routing keys.
    - Stream consumers use Streams protocol on `:5552`; choose group/offset strategy (earliest/latest).
    - Queue consumers use AMQP with `prefetch` and explicit acks.

- **Migration and rollout**

    1. Stop the broker: `./script/rmq_compose.sh down`.
    2. Remove existing data directory if topology changes require clean state: `rm -rf ./data/rabbitmq`.
    3. Apply updated configuration files.
    4. Start the broker: `./script/rmq_compose.sh up -d`.
    5. Verify topology in Management UI.
    6. Retarget producers/consumers to new routing keys.

- **Verification**

    - Management UI → Exchanges: verify `crypto-scout-exchange` and `dlx-exchange` exist.
    - Management UI → Queues: verify streams (`bybit-stream`, `bybit-ta-stream`, `crypto-scout-stream`) and queues
      (`collector-queue`, `chatbot-queue`, `analyst-queue`, `dlx-queue`) exist.
    - Publish test messages with each routing key and confirm delivery.
    - Verify Streams listener on `:5552` is reachable.
    - Confirm port `15692` is no longer exposed: `podman port crypto-scout-mq`.
