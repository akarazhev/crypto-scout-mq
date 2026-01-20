# Issue 16: Perform configuration review of the `crypto-scout-mq` project

The first version of the `crypto-scout-mq` project has been done now. Let's perform the configuration review to be
sure that the project is ready for production and there are no issues. Let's check if there is anything that can be
optimized and what can be done better.

## Roles

Take the following roles:

- Expert devops engineer.
- Expert technical writer.

## Conditions

- Rely on the current implementation of the `crypto-scout-mq` project.
- Double-check your proposal and make sure that they are correct and haven't missed any important points.
- Implementation must be production ready.
- Use the best practices and design patterns.

## Constraints

- Use the current technological stack, that's: `ActiveJ 6.0`, `Java 25`, `maven 3.9.1`, `podman 5.6.2`,
  `podman-compose 1.5.0`.
- Follow the current configuration style.
- Do not hallucinate.

## Tasks

- As the `expert devops engineer` perform configuration review of the `crypto-scout-mq` project and verify if this is
  ready for production and there are no issues. Check if there is anything that can be optimized and what can be done
  better.
- As the `expert devops engineer` recheck your proposal and make sure that they are correct and haven't missed any
  important points.
- As the `expert technical writer` update the `16-perform-config-review.md` file with your resolution.

---

## Resolution

### Configuration review (2025-12-13)

- **[verdict]** Ready for production in a single-node topology. Two minor script issues identified and fixed.

### Files reviewed

| File                               | Status                |
|------------------------------------|-----------------------|
| `podman-compose.yml`               | ✅ Production-ready    |
| `rabbitmq/rabbitmq.conf`           | ✅ Production-ready    |
| `rabbitmq/definitions.json`        | ✅ Production-ready    |
| `rabbitmq/enabled_plugins`         | ✅ Production-ready    |
| `secret/rabbitmq.env`              | ✅ Properly gitignored |
| `secret/rabbitmq.env.example`      | ✅ Documented          |
| `secret/README.md`                 | ✅ Clear instructions  |
| `script/rmq_compose.sh`            | ⚠️ Minor fix needed   |
| `script/rmq_user.sh`               | ✅ Production-ready    |
| `script/network.sh`                | ⚠️ Minor fix needed   |
| `README.md`                        | ✅ Comprehensive       |
| `doc/rabbitmq-production-setup.md` | ✅ Comprehensive       |
| `.gitignore`                       | ✅ Secrets excluded    |

### Strengths (production-ready features)

1. **Image pinning**: `rabbitmq:4.1.4-management` ensures deterministic deployments.
2. **Security hardening**:
    - `no-new-privileges=true` prevents privilege escalation.
    - `init: true` ensures proper signal handling and zombie reaping.
    - `pids_limit: 1024` prevents fork bombs.
    - `tmpfs: /tmp` with `nodev,nosuid` for ephemeral data.
    - Read-only config mounts (`enabled_plugins`, `rabbitmq.conf`, `definitions.json`).
    - Management UI bound to loopback only (`127.0.0.1:15672`).
    - AMQP/Streams ports not exposed to host (container network only).
3. **Resource limits**:
    - `cpus: "2.0"`, `mem_limit: "1g"`, `mem_reservation: "512m"`.
    - `nofile: 65536` ulimits prevent file descriptor exhaustion.
    - `disk_free_limit.absolute = 2GB` and `vm_memory_high_watermark.relative = 0.6` for broker protection.
4. **Healthcheck**: `rabbitmq-diagnostics -q ping` with `start_period: 30s`, `interval: 10s`, `retries: 5`.
5. **Graceful shutdown**: `stop_grace_period: 1m`, `stop_signal: SIGTERM`.
6. **Dead-letter infrastructure**: `dlx-exchange` → `dlx-queue` (TTL=7d) for failed message handling.
7. **Backpressure protection**: Classic queues with lazy mode, `reject-publish` overflow, TTL=6h, max length 2500.
8. **Stream retention**: Policy `stream-retention` enforces `max-age=1D`, `max-length-bytes=2GB`,
   `stream-max-segment-size-bytes=100MB` for `.*-stream$` queues.
9. **Secrets management**: Erlang cookie via `env_file`, gitignored, with documented generation procedure.
10. **User provisioning**: Users not embedded in definitions; created post-deploy via `script/rmq_user.sh`.
11. **External network**: `crypto-scout-bridge` isolates inter-service communication.
12. **Operational tooling**: `rmq_compose.sh` provides health waits, safer defaults; `rmq_user.sh` handles user
    lifecycle.

### Issues identified

#### Issue 1: Stale Prometheus reference in `rmq_compose.sh`

- **Location**: `script/rmq_compose.sh`, line 128.
- **Problem**: `print_endpoints()` function references Prometheus metrics endpoint (`http://localhost:15692/metrics`)
  which was removed in the 2025-12-10 topology update.
- **Impact**: Low — cosmetic; endpoint is unreachable but does not affect functionality.
- **Fix**: Remove the Prometheus line from `print_endpoints()`.

#### Issue 2: `network.sh` lacks error handling

- **Location**: `script/network.sh`.
- **Problem**: Script lacks `set -e` and does not handle the case where the network already exists (will fail on
  re-run).
- **Impact**: Low — script fails noisily if network exists; user must manually handle.
- **Fix**: Add `set -e` and idempotent network creation.

### Optimizations considered

| Optimization                                          | Status          | Rationale                                                  |
|-------------------------------------------------------|-----------------|------------------------------------------------------------|
| Remove Prometheus reference from `rmq_compose.sh`     | **Recommended** | Aligns script output with current configuration            |
| Improve `network.sh` robustness                       | **Recommended** | Makes script idempotent and production-friendly            |
| Add `consumer_timeout` for stuck consumers            | Optional        | Default (30min) is reasonable; tune per workload           |
| Add log rotation configuration                        | Optional        | Host-level log rotation typically sufficient               |
| Remove redundant queue arguments (policy covers them) | Not recommended | Queue arguments serve as documentation and fallback        |
| Enable TLS for AMQP/Streams/Management                | Optional        | Environment-specific; documented in recommendations        |
| Add `cap_drop: ["ALL"]`                               | Optional        | Requires thorough testing; current hardening is sufficient |

### Fixes applied

#### Fix 1: Remove Prometheus reference from `rmq_compose.sh`

```bash
# Before (line 128)
- Prometheus metrics: http://localhost:15692/metrics

# After
(line removed)
```

#### Fix 2: Improve `network.sh` robustness

```bash
#!/bin/bash
set -Eeuo pipefail

NETWORK_NAME="crypto-scout-bridge"

if podman network exists "$NETWORK_NAME" 2>/dev/null; then
  echo "[INFO] Network '$NETWORK_NAME' already exists."
else
  echo "[INFO] Creating network '$NETWORK_NAME'..."
  podman network create "$NETWORK_NAME"
fi

podman network inspect "$NETWORK_NAME"
```

### Recheck verification

| Check                      | Result                                             |
|----------------------------|----------------------------------------------------|
| Image version pinned       | ✅ `rabbitmq:4.1.4-management`                      |
| Plugins correct            | ✅ `rabbitmq_management`, `rabbitmq_stream`         |
| Streams configured         | ✅ 3 streams with retention policy                  |
| Classic queues configured  | ✅ 4 queues with DLX routing                        |
| Exchanges configured       | ✅ `crypto-scout-exchange`, `dlx-exchange` (direct) |
| Bindings complete          | ✅ 7 bindings with correct routing keys             |
| Healthcheck present        | ✅ `rabbitmq-diagnostics -q ping`                   |
| Resource limits set        | ✅ CPU, memory, ulimits, disk/memory watermarks     |
| Security hardening applied | ✅ All compose security options present             |
| Secrets gitignored         | ✅ `secret/*.env` in `.gitignore`                   |
| Network isolation          | ✅ AMQP/Streams container-only; Management loopback |
| Graceful shutdown          | ✅ `SIGTERM`, 1m grace period                       |
| Documentation complete     | ✅ README.md and production setup guide             |

### Conclusion

The `crypto-scout-mq` project is **production-ready** for single-node deployment. Two minor script issues were
identified and fixed:

1. Removed stale Prometheus endpoint reference from `rmq_compose.sh`.
2. Improved `network.sh` with error handling and idempotent network creation.

No changes required to core RabbitMQ configuration (`rabbitmq.conf`, `definitions.json`, `enabled_plugins`) or
container definition (`podman-compose.yml`).

### Recommendations for future consideration

- **TLS**: Enable TLS for AMQP, Streams, and Management when crossing untrusted networks.
- **Backups**: Schedule regular snapshots of `./data/rabbitmq` and perform restore drills.
- **Monitoring**: Consider re-enabling Prometheus plugin if metrics scraping is needed; update `enabled_plugins` and
  expose port `15692`.
- **Clustering**: For HA requirements, deploy multiple nodes with quorum queues/policies.