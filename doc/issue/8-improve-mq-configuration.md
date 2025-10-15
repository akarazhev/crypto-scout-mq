# Issue 7: Improve `crypto-scout-mq` configuration

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
  important points.
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