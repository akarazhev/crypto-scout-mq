# crypto-scout-mq

Production-ready RabbitMQ service for the crypto-scout stack (AMQP + Streams + Prometheus), deployed via Podman Compose
with a pre-provisioned messaging topology.

## Features

- RabbitMQ 4.1.4-management image
- Enabled plugins: management, prometheus, stream, consistent-hash exchange (`rabbitmq/enabled_plugins`)
- Pre-provisioned topology via `rabbitmq/definitions.json`:
    - Exchanges: `crypto-exchange`, `collector-exchange`, `metrics-exchange` (topic)
    - Streams: `crypto-bybit-stream`, `metrics-bybit-stream`, `metrics-cmc-stream` (durable, `x-queue-type: stream`)
    - Queues: `crypto-scout-collector-queue`
    - Bindings: `crypto-bybit`, `crypto-scout-collector`, `metrics-bybit`, `metrics-cmc`
- Prometheus metrics on `:15692/metrics`
- Healthcheck, graceful shutdown, raised file descriptor limits
- Persistent data volume

## Repository layout

- `podman-compose.yml` — container definition (ports, volumes, healthcheck, ulimits)
- `rabbitmq/` — `enabled_plugins`, `rabbitmq.conf`, `definitions.json`
- `secrets/` — instructions and example for `rabbitmq.env` (`RABBITMQ_ERLANG_COOKIE`)
- `script/rmq_user.sh` — helper to create/update users and permissions
- `doc/` — production setup notes and guides

## Prerequisites

- Podman and Podman Compose plugin
- macOS/Linux shell with `openssl` (optional, for generating secrets)

## Quick start

1) Prepare secrets (see `secrets/README.md`). Example to generate a strong Erlang cookie:

```bash
mkdir -p ./secrets
cp ./secrets/rabbitmq.env.example ./secrets/rabbitmq.env
COOKIE=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)
printf "RABBITMQ_ERLANG_COOKIE=%s\n" "$COOKIE" > ./secrets/rabbitmq.env
chmod 600 ./secrets/rabbitmq.env
```

2) Start the broker:

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
```

## Configuration highlights (`rabbitmq/rabbitmq.conf`)

```ini
stream.listeners.tcp.1 = 5552
load_definitions = /etc/rabbitmq/definitions.json
prometheus.tcp.port = 15692
prometheus.tcp.ip = 0.0.0.0
management.rates_mode = basic
deprecated_features.permit.management_metrics_collection = true
disk_free_limit.absolute = 2GB
vm_memory_high_watermark.relative = 0.6
```

## Ports

- 5672: AMQP
- 5552: Streams
- 15672: Management UI
- 15692: Prometheus metrics

## Persistence and backups

- Data directory is persisted at `./data/rabbitmq:/var/lib/rabbitmq`.
- Back up the data directory regularly for durability and disaster recovery.

## Security notes

- Keep `./secrets/rabbitmq.env` out of version control; rotate the Erlang cookie per environment.
- Create per-service users with least-privilege permissions.
- Consider enabling TLS for AMQP, Streams, and Management in production networks.

## Troubleshooting

- If the Erlang cookie changes after first start, the node identity changes. For a clean re-init, stop the container and
  remove `./data/rabbitmq` (this erases broker state).
- Check container health: `podman inspect -f '{{.State.Health.Status}}' crypto-scout-mq`

## License

See `LICENSE`.
