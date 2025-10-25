# crypto-scout-mq

Production-ready RabbitMQ service for the crypto-scout stack (AMQP + Streams + Prometheus), deployed via Podman Compose
with a pre-provisioned messaging topology.

## Features

- RabbitMQ 4.1.4-management image
- Enabled plugins: management, prometheus, stream (`rabbitmq/enabled_plugins`)
- Pre-provisioned topology via `rabbitmq/definitions.json`:
    - Exchanges: `bybit-exchange`, `crypto-scout-exchange`, `parser-exchange` (direct)
    - Streams: `bybit-crypto-stream`, `bybit-ta-crypto-stream`, `bybit-parser-stream`, `cmc-parser-stream` (durable,
      `x-queue-type: stream`)
    - Queues: `collector-queue`, `chatbot-queue`, `analyst-queue`
    - Bindings: `bybit`, `bybit-ta`, `collector`, `chatbot`, `analyst`, `bybit-parser`, `cmc-parser`
- Stream retention: `x-max-age=7D`, `x-max-length-bytes=2GB`, `x-stream-max-segment-size-bytes=100MB` (evaluated per
  segment; operator policies can override queue arguments)
- Prometheus metrics on `:15692/metrics`
- Graceful shutdown
- Persistent data volume
- Security hardening in compose: read-only config mounts (`enabled_plugins`, `rabbitmq.conf`, `definitions.json`),
  `no-new-privileges`, `init`, `pids_limit`, tmpfs for `/tmp`, graceful `SIGTERM`
- Collector, chatbot, analyst queues hardened: lazy mode and `reject-publish` overflow for `collector-queue`,
  `chatbot-queue`, and `analyst-queue`
- Stream retention enforced via policy `stream-retention` for `.*-stream$` queues

## Repository layout

- `podman-compose.yml` — container definition (ports, volumes, healthcheck, ulimits)
- `rabbitmq/` — `enabled_plugins`, `rabbitmq.conf`, `definitions.json`
- `secret/` — instructions and example for `rabbitmq.env` (`RABBITMQ_ERLANG_COOKIE`)
- `script/rmq_user.sh` — helper to create/update users and permissions
- `script/rmq_compose.sh` — production runner to manage Podman Compose (up/down/logs/status/wait)
- `doc/` — production setup notes and guides

## Prerequisites

- Podman and Podman Compose plugin
- macOS/Linux shell with `openssl` (optional, for generating secret)

## Quick start

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
- Metrics: `curl -s http://localhost:15692/metrics | head`
- Health: `podman ps` should show the container as healthy

## Provision an admin user

Definitions do not include users by design. Create an administrator:

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
prometheus.tcp.port = 15692
prometheus.tcp.ip = 0.0.0.0
management.tcp.ip = 0.0.0.0
management.rates_mode = basic
disk_free_limit.absolute = 2GB
vm_memory_high_watermark.relative = 0.6
cluster_formation.peer_discovery_backend = classic_config
cluster_formation.classic_config.nodes.1 = rabbit@crypto_scout_mq
```

## Ports

- 5672: AMQP
- 5552: Streams
- 15672: Management UI
- 15692: Prometheus metrics

## External access (Streams advertised host/port)

By default, the Streams advertised address is set for inter-container connectivity on the Podman network:

- Host: `crypto_scout_mq`
- Port: `5552`

For clients outside the host (public access or across NAT), edit `rabbitmq/rabbitmq.conf` and set:

```ini
stream.advertised_host = <public-dns-or-ip>
stream.advertised_port = <public-port>
```

Then restart the service. Ensure your firewall/NAT exposes the Streams port (default `5552`).

Verification:

- Management UI: http://<public-host>:15672/
- Metrics:      http://<public-host>:15692/metrics
- Streams:      connect a Streams client to `<public-host>:<port>` and confirm it does not redirect to `localhost`.

## Persistence and backups

- Data directory is persisted at `./data/rabbitmq:/var/lib/rabbitmq`.
- Back up the data directory regularly for durability and disaster recovery.

## Security notes

- Management UI (15672) and Prometheus (15692) are bound to loopback via compose (`127.0.0.1:<port>:<port>`). For
  remote access, use an SSH tunnel or place a reverse proxy with TLS and auth in front.
- Keep `./secret/rabbitmq.env` out of version control; rotate the Erlang cookie per environment.
- Create per-service users with least-privilege permissions.

## Troubleshooting

- If the Erlang cookie changes after first start, the node identity changes. For a clean re-init, stop the container and
  remove `./data/rabbitmq` (this erases broker state).
- Check container health: `podman inspect -f '{{.State.Health.Status}}' crypto-scout-mq`

## License

See `LICENSE`.
