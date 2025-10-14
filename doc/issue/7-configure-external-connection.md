# Issue 7: Configure external connection

In this `crypto-scout-mq` project we are going to configure external the connection to RabbitMQ.

## Roles

Take the following roles:

- Expert dev-opts engineer.
- Expert technical writer.

## Conditions

- Use the best practices and design patterns.
- Do not hallucinate.

## Tasks

- As the expert dev-opts engineer review the current `rabbitmq.conf` config and `podman-compose.yml` files in 
- `crypto-scout-mq` project and update them to support the external connection to RabbitMQ.
- As the expert dev-opts engineer recheck your proposal and make sure that they are correct and haven't missed any
  important points.
- As the technical writer update the `README.md` and `rabbitmq-production-setup.md` files with your results.
- As the technical writer update the `7-configure-external-connection.md` file with your resolution.

## Resolution

- **[Problem]** `stream.advertised_host` was set to `localhost`, which breaks external clients of the Streams protocol
  because the broker advertises a non-routable host for reconnections.
- **[Solution]** Bind Streams and Management to all interfaces and set a static advertised address suitable for
  inter-container connectivity on the Podman network. Default to `crypto_scout_mq:5552`. For public/external clients,
  edit `rabbitmq/rabbitmq.conf` to set a routable DNS name/IP and port.

### Changes

- **[`rabbitmq/rabbitmq.conf`]**
  - `stream.listeners.tcp.1 = 0.0.0.0:5552`
  - `stream.advertised_host = crypto_scout_mq`
  - `stream.advertised_port = 5552`
  - `management.tcp.ip = 0.0.0.0`

- **[`podman-compose.yml`]**
  - Ports remain published: `5672`, `5552`, `15672`, `15692`.

- **Docs updated**
  - [`README.md`]: Added "External access" section and updated config highlights.
  - [`doc/rabbitmq-production-setup.md`]: Added external access guidance, updated config and compose highlights.

### How to configure external access

1. Decide the public address for Streams (DNS or IP) and port (typically `5552`).
2. Edit `rabbitmq/rabbitmq.conf`:
   ```ini
   stream.advertised_host = <public-dns-or-ip>
   stream.advertised_port = <public-port>
   ```
3. Restart the stack:
   ```bash
   ./script/rmq_compose.sh up -d
   # or: podman compose -f podman-compose.yml up -d
   ```

### Verification

- **[Management]** Open `http://<public-host>:15672/`.
- **[Metrics]** `curl -s http://<public-host>:15692/metrics | head`.
- **[Streams]** From a client host, ensure `nc -vz <public-host> 5552` succeeds. Use a Streams client to connect to
  `<public-host>:<port>` and confirm it does not get redirected to `localhost`.
- **[Logs]** Check container logs for the effective advertised host/port values at startup.

### Recheck

- **Ports** are published in `podman-compose.yml` and mapped to the container; no additional NAT rules are required on
  the host beyond firewall allowances.
- **Bindings** ensure listeners are on `0.0.0.0` inside the container; external reachability depends on host firewall
  and network routing.
- **Static configuration** by default for inter-container DNS. For public exposure, update `rabbitmq.conf` per
  environment and restart.
- **Security**: TLS remains recommended for production networks but is environment-specific and not enabled here.