# Issue 13: Perform configuration review of the `crypto-scout-mq` project

The first version of the `crypto-scout-mq` project has been done now. Let's perform the configuration review to be
sure that the project is ready for production and there are no issues. Let's check if there is anything that can be
optimized and what can be done better.

## Roles

Take the following roles:

- Expert dev opts engineer.
- Expert technical writer.

## Conditions

- Use the best practices and design patterns.
- Use the current technology stack, that's: `rabbitmq:4.1.4-management`, `podman 5.6.2`, `podman-compose 1.5.0`.
- Configuration is `rabbitmq/definitions.json`, `rabbitmq/enabled_plugins`, `rabbitmq/rabbitmq.conf`,
  `podman-compose.yml`, `secret/rabbitmq.env.example`, `secret/README.md`.
- Do not hallucinate.

## Tasks

- As the `expert dev opts engineer` perform configuration review of the `crypto-scout-mq` project and verify if this
  is ready for production and there are no issues. Check if there is anything that can be optimized and what can be done
  better.
- As the `expert dev opts engineer` recheck your proposal and make sure that they are correct and haven't missed any
  important points.
- As the `expert technical writer` update the `README.md` and `rebbitmq-production-setup.md` files with your results.
- As the `expert technical writer` update the `13-perform-configuration-review.md` file with your resolution.

## Resolution (2025-10-25)

### Findings

- **[configs reviewed]** `podman-compose.yml`, `rabbitmq/rabbitmq.conf`, `rabbitmq/definitions.json`,
  `rabbitmq/enabled_plugins`, `secret/README.md`, `secret/rabbitmq.env.example`.
- **[observability]** Prometheus metrics exposed on `:15692`; management UI `:15672`; Streams listener `:5552` with
  static advertised host/port.
- **[topology]** Streams and classic queues match `rabbitmq/definitions.json`; retention policy `stream-retention` in
  place; hardened classic queues (`lazy`, `reject-publish`).
- **[reliability]** Healthcheck configured; persistent volume; ulimit `nofile=65536`; graceful shutdown.
- **[security]** No users in definitions; secrets via `./secret/rabbitmq.env` (git ignored); hardening in compose
  (`no-new-privileges`, read-only config mounts, `pids_limit`, tmpfs `/tmp`).

### Readiness verdict

- **Ready for production (single-node)** given current scope and constraints.

### Recommendations (optional hardening)

- **[restrict exposure]** If not needed publicly, bind management and metrics to loopback in `podman-compose.yml`:
  `127.0.0.1:15672:15672`, `127.0.0.1:15692:15692`, or set `management.tcp.ip = 127.0.0.1` and front with TLS proxy.
- **[resource limits]** Add CPU/memory limits in `podman-compose.yml` per host capacity.
- **[extra hardening]** Consider `cap_drop: ["ALL"]` (non-privileged ports), `read_only: true` with explicit writable
  mounts for `/var/lib/rabbitmq` and tmpfs for `/tmp` (validate before enabling).
- **[TLS]** Enable TLS for AMQP/Streams/Management on untrusted networks.
- **[backups]** Snapshot `./data/rabbitmq` regularly; test restore.
- **[streams external]** For external clients, set `stream.advertised_host/port` to a routable address and open
  firewall.
- **[network]** Ensure external network `crypto-scout-bridge` exists (use `script/network.sh`).

### Documentation updates

- **doc/rabbitmq-production-setup.md**: Appended "Configuration review (2025-10-25)" section with detailed guidance.

### Status

- **Resolved**. Project is production-ready for single-node; optimizations are optional and environment-dependent.