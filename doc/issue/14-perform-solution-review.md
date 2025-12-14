# Issue 14: Perform solution review of the `crypto-scout-mq` project

The first version of the `crypto-scout-mq` project has been done now. Let's perform the solution review to be sure
that the project is ready for production and there are no issues. Let's check if there is anything that can be optimized
and what can be done better.

## Roles

Take the following roles:

- Expert solution architect.
- Expert technical writer.

## Conditions

- Use the best practices and design patterns.
- Use the current technology stack, that's: `rabbitmq:4.1.4-management`, `podman 5.6.2`, `podman-compose 1.5.0`.
- Configuration is `rabbitmq/definitions.json`, `rabbitmq/enabled_plugins`, `rabbitmq/rabbitmq.conf`,
  `podman-compose.yml`, `secret/rabbitmq.env.example`, `secret/README.md`.
- Do not hallucinate.

## Tasks

- As the `expert solution architect` perform solution review of the `crypto-scout-mq` project and verify if this is
  ready for production and there are no issues. Check if there is anything that can be optimized and what can be done
  better.
- As the `expert solution architect` recheck your proposal and make sure that they are correct and haven't missed any
  important points.
- As the `expert technical writer` update the `README.md` and `rabbitmq-production-setup.md` files with your results.
- As the `expert technical writer` update the `14-perform-solution-review.md` file with your resolution.

---

## Resolution (2025-10-27)

### Verdict

- **Ready for production (single-node)**. The deployment is production-ready for a standalone broker with Streams.

### Scope reviewed

- Config: `rabbitmq/rabbitmq.conf`, `rabbitmq/enabled_plugins`.
- Topology: `rabbitmq/definitions.json` (exchanges, streams, queues, bindings, policy).
- Runtime: `podman-compose.yml` (healthcheck, ulimits, security, ports, volumes, external network).
- Secrets: `secret/README.md`, `secret/rabbitmq.env.example`.
- Scripts: `script/rmq_compose.sh`, `script/rmq_user.sh`, `script/network.sh`.

### Findings (grounded in repo)

- **Image pinning**: `rabbitmq:4.1.4-management` in `podman-compose.yml`.
- **Plugins**: `rabbitmq_management`, `rabbitmq_stream` in `rabbitmq/enabled_plugins`.
- **Streams and queues**: Retention policy `stream-retention` for `.*-stream$`. Classic queues (`collector-queue`,
  `chatbot-queue`, `analyst-queue`) hardened with TTL=6h, max length 2500, lazy mode, `x-overflow=reject-publish`.
- **Exchanges**: Direct type for `crypto-scout-exchange`, `dlx-exchange`.
- **Security/operability**: Read-only config mounts, `no-new-privileges`, tmpfs `/tmp`, `pids_limit`,
  `stop_grace_period=1m`, healthcheck.
- **Ports**: Management bound to loopback; Streams and AMQP container-network only.
- **External network**: `podman-compose.yml` uses external network `crypto-scout-bridge` (now documented).
- **Streams external access**: `stream.listeners.tcp.1`, `stream.advertised_host`, `stream.advertised_port` set in
  `rabbitmq/rabbitmq.conf`.

### Optimizations and recommendations (optional)

- **Network exposure**: Keep 15672 loopback-only; use SSH tunnel or reverse proxy with TLS/auth for remote access.
- **TLS**: Enable TLS for AMQP/Streams/Management when traversing untrusted networks.
- **Container hardening**: Consider `cap_drop: ["ALL"]` and `read_only: true` with explicit writable mounts (
  `/var/lib/rabbitmq`, tmpfs `/tmp`); test thoroughly.
- **Resource tuning**: Adjust `cpus`, `mem_limit`, `disk_free_limit.absolute`, `vm_memory_high_watermark.relative` per
  workload/host.
- **Backups and logs**: Schedule backups for `./data/rabbitmq`; ensure host/container log rotation.

### Documentation updates applied

- `README.md`:
    - Added external Podman network prerequisite and `script/network.sh` reference.
    - Appended a concise production readiness review note.
- `doc/rabbitmq-production-setup.md`:
    - Inserted network prerequisite in Operations.
    - Added "Solution review (2025-10-27)" section with verdict, validations, and recommendations.

No code/config changes required at this time; documentation improvements only.