# Secrets for RabbitMQ (production)

This folder holds local secrets used by `podman-compose.yml` for RabbitMQ. Files here are ignored by git (see project
`.gitignore`).

Required files:

- `rabbitmq.env` — env file providing:
    - `RABBITMQ_ERLANG_COOKIE`

Quick start

1) Create the directory if missing:
   mkdir -p ./secrets

2) Create the env file from example:
   cp ./secrets/rabbitmq.env.example ./secrets/rabbitmq.env
   # Or generate strong values:
   COOKIE=$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 48)
   printf "RABBITMQ_ERLANG_COOKIE=%s\n" "$COOKIE" > ./secrets/rabbitmq.env

3) Restrict permissions (recommended on Unix/macOS):
   chmod 600 ./secrets/rabbitmq.env

Notes

- The cookie identifies a node/cluster. Changing it after first start will create a new node identity; for existing data
  directories, you may need to remove `./data/rabbitmq` to reinitialize.
- Never commit real secrets. Only commit example files.
