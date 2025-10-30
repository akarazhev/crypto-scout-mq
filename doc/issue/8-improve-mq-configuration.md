# Issue 8: Improve `crypto-scout-mq` configuration

In this `crypto-scout-mq` project we are going to improve the configuration and verify if this is production ready and
ready to manage a lot of the data.

## Roles

Take the following roles:

- Expert dev-opts engineer.
- Expert technical writer.

## Conditions

- Use the best practices and design patterns.
- Do not hallucinate.

## Tasks

- As the expert dev-opts engineer review the current `rabbitmq.conf`, `definitions.json`, `enabled_plugins` configs
- and `podman-compose.yml` file in `crypto-scout-mq` project then verify and improve it to be sure that it is production
  ready to manage a lot of the data. Take the `podman-compose.yml` file as a sample defined below.
- As the expert dev-opts engineer recheck your proposal and make sure that they are correct and haven't missed any
- As the technical writer update the `README.md` and `rabbitmq-production-setup.md` files with your results.
- As the technical writer update the `8-improve-mq-connection.md` file with your resolution.

### Sample `podman-compose.yml` file

```yaml
services:
  crypto-scout-client:
    build:
      context: .
      dockerfile: Dockerfile
    image: crypto-scout-client:0.0.1
    container_name: crypto-scout-client
    cpus: "1.00"
    memory: 1G
    env_file:
      - secret/client.env
    environment:
      TZ: UTC
    networks:
      - crypto-scout-bridge
    ports:
      - "8080:8080"
    security_opt:
      - no-new-privileges=true
    read_only: true
    tmpfs:
      - /tmp:rw,size=64m,mode=1777,nodev,nosuid
    cap_drop:
      - ALL
    user: "10001:10001"
    init: true
    pids_limit: 256
    ulimits:
      nofile:
        soft: 4096
        hard: 4096
    restart: unless-stopped
    stop_signal: SIGTERM
    stop_grace_period: 30s
    healthcheck:
      test: [ "CMD-SHELL", "curl -f http://localhost:8080/health || exit 1" ]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 30s

networks:
  crypto-scout-bridge:
    name: crypto-scout-bridge
    external: true
```

## Resolution

- **[Compose hardening]** Updated `podman-compose.yml` to:
    - Mount `rabbitmq/enabled_plugins`, `rabbitmq/rabbitmq.conf`, `rabbitmq/definitions.json` as read-only.
    - Add `security_opt: [no-new-privileges=true]`, `init: true`, `pids_limit: 1024`,
      `stop_signal: SIGTERM`, `tmpfs: /tmp`.
    - Keep data volume `./data/rabbitmq:/var/lib/rabbitmq` and published ports `5672`, `5552`, `15672`, `15692`
      unchanged.

- **[Topology improvements]** Updated `rabbitmq/definitions.json`:
    - Added policy `stream-retention` for queues matching `.*-stream$` to enforce retention: `max-length-bytes=2GB`,
      `max-age=1D`, `stream-max-segment-size-bytes=100MB`.
    - Ensured `metrics-bybit-stream` and `metrics-cmc-stream` explicitly declare `x-queue-type=stream` with the same
      retention arguments.
    - Hardened `collector-queue` with `x-queue-mode=lazy` and `x-overflow=reject-publish`.

- **[Config validation]** `rabbitmq/rabbitmq.conf` already production-safe (Streams listener and advertised host/port;
  Prometheus and Management listeners; disk/memory watermarks).

- **[Docs updated]**
    - `README.md`: Features list documents hardening, collector queue, and retention policy.
    - `doc/rabbitmq-production-setup.md`: Added compose hardening, Policies section, and readiness/backpressure notes.

### Recheck

- **Security**: Config mounts are read-only; `no-new-privileges`; PID limit; tmpfs for `/tmp`. Delete the default `guest`
  user after provisioning.
- **Reliability**: Disk and memory watermarks configured; healthcheck present; graceful shutdown.
- **Streams**: Streams listener and advertised address configured; retention consistent via policy; stream port `5552`
  exposed.
- **Backpressure**: Collector queue uses lazy mode and rejects publish on overflow.
- **Observability**: Prometheus `:15692`; Management `:15672`.

### Next steps

- Create admin users and delete the default `guest` user:
  ```bash
  ./script/rmq_user.sh -u admin -p 'changeMeStrong!' -t administrator -y
  podman exec -it crypto-scout-mq rabbitmqctl delete_user guest
  ```
- If exposing to public networks, configure TLS for AMQP/Streams/Management and set external
  `stream.advertised_host/port`.