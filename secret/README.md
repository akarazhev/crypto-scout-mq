# Secret for RabbitMQ (production)

This folder holds a local secret used by `podman-compose.yml` for RabbitMQ. Files here are ignored by git (see project
`.gitignore`).

Required files:

- `rabbitmq.env` — env file providing:
    - `RABBITMQ_ERLANG_COOKIE`

Quick start

1) Create the directory if missing:
   mkdir -p ./secret

2) Create the env file from example:
   ```bash
   cp ./secret/rabbitmq.env.example ./secret/rabbitmq.env
   # Or generate strong values:
   COOKIE=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)
   printf "RABBITMQ_ERLANG_COOKIE=%s\n" "$COOKIE" > ./secret/rabbitmq.env
   ```
3) Restrict permissions (recommended on Unix/macOS):
   chmod 600 ./secret/rabbitmq.env

Notes

- The cookie identifies a node/cluster. Changing it after first start will create a new node identity; for existing data
  directories, you may need to remove `./data/rabbitmq` to reinitialize.
- Never commit the real secret. Only commit example files.
