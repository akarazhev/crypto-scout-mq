# crypto-scout-mq

Production-ready RabbitMQ service for the crypto-scout stack (AMQP + Streams), deployed via Podman Compose
with a pre-provisioned messaging topology.

## Features

- RabbitMQ 4.1.4-management image
- Enabled plugins: management, stream (`rabbitmq/enabled_plugins`)
- Pre-provisioned topology via `rabbitmq/definitions.json`:
    - Exchanges: `crypto-scout-exchange`, `dlx-exchange` (direct)
    - Streams: `bybit-stream`, `crypto-scout-stream` (durable, `x-queue-type: stream`)
    - Queues: `collector-queue`, `chatbot-queue`, `dlx-queue`
    - Bindings: `bybit`, `crypto-scout`, `collector`, `chatbot`, `dlx`
- Stream retention policy (`stream-retention`): max 2GB or 1 day, 100MB segments
- Dead-letter exchange (`dlx-exchange`) with `dlx-queue` (max 10k messages, 7 day TTL)
- DLX retention policy (`dlx-retention`): max 10k messages, 7 day TTL, reject-publish overflow
- Graceful shutdown
- Persistent data volume
- Security hardening in compose: read-only config mounts (`enabled_plugins`, `rabbitmq.conf`, `definitions.json`),
  `no-new-privileges`, `init`, `pids_limit`, tmpfs for `/tmp`, graceful `SIGTERM`
- Collector, chatbot queues hardened: lazy mode, `reject-publish` overflow, and dead-letter routing
- Retention policies: `stream-retention` for `.*-stream$` queues, `dlx-retention` for `dlx-queue`

## Repository layout

- `podman-compose.yml` — container definition (ports, volumes, healthcheck, ulimits)
- `rabbitmq/` — `enabled_plugins`, `rabbitmq.conf`, `definitions.json`
- `secret/` — instructions and example for `rabbitmq.env` (`RABBITMQ_ERLANG_COOKIE`)
- `script/rmq_user.sh` — helper to create/update users and permissions
- `script/rmq_compose.sh` — production runner to manage Podman Compose (up/down/logs/status/wait)
- `script/network.sh` — helper to create the external Podman network `crypto-scout-bridge`

## Prerequisites

- Podman and Podman Compose plugin
- macOS/Linux shell with `openssl` (optional, for generating secret)

## Quick start

0) Ensure Podman network exists (compose uses an external network `crypto-scout-bridge`):

Recommended:

```bash
./script/network.sh
```

Alternative:

```bash
podman network create crypto-scout-bridge
```

1) Prepare secret (see `secret/README.md`). Example to generate a strong Erlang cookie:

```bash
mkdir -p ./secret
cp ./secret/rabbitmq.env.example ./secret/rabbitmq.env
COOKIE=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)
printf "RABBITMQ_ERLANG_COOKIE=%s\n" "$COOKIE" > ./secret/rabbitmq.env
chmod 600 ./secret/rabbitmq.env
```

2) Start the broker:

Recommended (runner script):

```bash
./script/rmq_compose.sh up -d
```

Alternative (raw compose):

```bash
podman compose -f podman-compose.yml up -d
```

3) Verify:

- Management UI: http://localhost:15672/
- Health: `podman ps` should show the container as healthy

## Provision users

Definitions do not include users by design (credentials created separately after first run). Create an administrator:

```bash
./script/rmq_user.sh -u admin -p 'changeMeStrong!' -t administrator -y
```

Or manually in the container:

```bash
podman exec -it crypto-scout-mq rabbitmqctl add_user admin 'changeMeStrong!'
podman exec -it crypto-scout-mq rabbitmqctl set_user_tags admin administrator
podman exec -it crypto-scout-mq rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
podman exec -it crypto-scout-mq rabbitmqctl delete_user guest
```

## Service management (runner script)

Use `script/rmq_compose.sh` to manage the service in a production-friendly way (health waits, safer defaults):

- **Start detached (waits for health):**
  ```bash
  ./script/rmq_compose.sh up -d
  ```
- **Start attached (foreground):**
  ```bash
  ./script/rmq_compose.sh up --attach
  ```
- **Stop (keep volumes):**
  ```bash
  ./script/rmq_compose.sh down
  ```
- **Stop and remove volumes (destructive):**
  ```bash
  ./script/rmq_compose.sh down --prune
  ```
- **Restart and wait:**
  ```bash
  ./script/rmq_compose.sh restart
  ```
- **Logs (follow):**
  ```bash
  ./script/rmq_compose.sh logs -f
  ```
- **Status and health:**
  ```bash
  ./script/rmq_compose.sh status
  ```
- **Wait for health:**
  ```bash
  ./script/rmq_compose.sh wait
  ```

Options:

- `-f, --file` to target a different compose file (default: `podman-compose.yml`).
- `-c, --container` to override container name (default: `crypto-scout-mq`).
- `--timeout` to adjust health wait (default: 120s).
- The script ensures `./secret/rabbitmq.env` exists before starting.

## Configuration highlights (`rabbitmq/rabbitmq.conf`)

```ini
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

## Ports

- 5672: AMQP (container network only)
- 5552: Streams (container network only)
- 15672: Management UI (localhost only)

## Container networking

AMQP (5672) and Streams (5552) are **not exposed to the host** — only to containers on the `crypto-scout-bridge`
network. Other services connect via:

- AMQP: `crypto-scout-mq:5672` or `crypto_scout_mq:5672`
- Streams: `crypto-scout-mq:5552` or `crypto_scout_mq:5552`

Management UI is exposed to localhost only (`127.0.0.1:15672`).

## Persistence and backups

- Data directory is persisted at `./data/rabbitmq:/var/lib/rabbitmq`.
- Back up the data directory regularly for durability and disaster recovery.

## Resource limits

- Resource limits in `podman-compose.yml`:
    - `cpus: "1.0"`
    - `mem_limit: "256m"`
    - `mem_reservation: "128m"`
- Tune these under `services.crypto-scout-mq` based on host capacity and SLOs.

## Security notes

- **No host-exposed AMQP/Streams ports**: Only containers on `crypto-scout-bridge` can reach 5672/5552.
- **Management UI (15672)** is bound to loopback (`127.0.0.1`). For remote access, use an SSH tunnel or reverse proxy
  with TLS and auth.
- Keep `./secret/rabbitmq.env` out of version control; rotate the Erlang cookie per environment.
- Create per-service users with scoped permissions after first run (see `script/rmq_user.sh`).

## Troubleshooting

- If the Erlang cookie changes after first start, the node identity changes. For a clean re-init, stop the container and
  remove `./data/rabbitmq` (this erases broker state).
- Check container health: `podman inspect -f '{{.State.Health.Status}}' crypto-scout-mq`

## License

See `LICENSE`.
