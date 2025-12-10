# Issue 15: Update queues, exchanges and bindings to make it production ready

In this `crypto-scout-mq` project we are going to update `queues`, `exchanges`, `bindings`, `routing keys` and make it
production ready. So let's review and update the project configuration with docs to reflect these changes.

## Roles

Take the following roles:

- Expert dev-opts engineer.
- Expert technical writer.

## Conditions

- Use the best practices and design patterns.
- Do not hallucinate.

## Constraints

- Use the current technology stack, that's: `rabbitmq:4.1.4-management`, `podman 5.6.2`, `podman-compose 1.5.0`.
- Configuration is `rabbitmq/definitions.json`, `rabbitmq/enabled_plugins`, `rabbitmq/rabbitmq.conf`,
  `podman-compose.yml`, `secret/rabbitmq.env.example`, `secret/README.md`.

## Tasks

- As the `expert dev-opts engineer` review the current `crypto-scout-mq` project and update it by updating `queues`,
  `exchanges`, `bindings`, `routing keys` to consume crypto data and interservice communication. Rely on the sample of
  `rabbitmq/definitions.json`.
- Recheck your proposal and make sure that they are correct and haven't missed any important points.

## Sample of `rabbitmq/definitions.json`

```json
{
  "rabbit_version": "4.1.4",
  "rabbitmq_version": "4.1.4",
  "product_name": "RabbitMQ",
  "product_version": "4.1.4",
  "users": [
    {
      "name": "crypto_scout_mq",
      "password_hash": "2xB5uNpCTDH0DPZxWUn5miYLbwQde5QKkx+gKKElY7msw2f8",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": [
        "management"
      ]
    }
  ],
  "vhosts": [
    {
      "name": "/",
      "description": "Default virtual host",
      "metadata": {
        "description": "Default virtual host",
        "default_queue_type": "classic"
      }
    }
  ],
  "permissions": [
    {
      "user": "crypto_scout_mq",
      "vhost": "/",
      "configure": "^(bybit|crypto-scout|collector|chatbot|analyst|dlx).*$",
      "write": "^(bybit|crypto-scout|collector|chatbot|analyst|dlx).*$",
      "read": "^(bybit|crypto-scout|collector|chatbot|analyst|dlx).*$"
    }
  ],
  "policies": [
    {
      "vhost": "/",
      "name": "stream-retention",
      "pattern": ".*-stream$",
      "definition": {
        "max-length-bytes": 2000000000,
        "max-age": "1D",
        "stream-max-segment-size-bytes": 100000000
      },
      "priority": 0,
      "apply-to": "queues"
    }
  ],
  "queues": [
    {
      "name": "bybit-stream",
      "vhost": "/",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-max-length-bytes": 2000000000,
        "x-max-age": "1D",
        "x-queue-type": "stream",
        "x-stream-max-segment-size-bytes": 100000000
      }
    },
    {
      "name": "bybit-ta-stream",
      "vhost": "/",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-max-length-bytes": 2000000000,
        "x-max-age": "1D",
        "x-queue-type": "stream",
        "x-stream-max-segment-size-bytes": 100000000
      }
    },
    {
      "name": "crypto-scout-stream",
      "vhost": "/",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-max-length-bytes": 2000000000,
        "x-max-age": "1D",
        "x-queue-type": "stream",
        "x-stream-max-segment-size-bytes": 100000000
      }
    },
    {
      "name": "collector-queue",
      "vhost": "/",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-max-length": 2500,
        "x-message-ttl": 21600000,
        "x-queue-mode": "lazy",
        "x-overflow": "reject-publish",
        "x-dead-letter-exchange": "dlx-exchange",
        "x-dead-letter-routing-key": "dlx"
      }
    },
    {
      "name": "chatbot-queue",
      "vhost": "/",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-max-length": 2500,
        "x-message-ttl": 21600000,
        "x-queue-mode": "lazy",
        "x-overflow": "reject-publish",
        "x-dead-letter-exchange": "dlx-exchange",
        "x-dead-letter-routing-key": "dlx"
      }
    },
    {
      "name": "analyst-queue",
      "vhost": "/",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-max-length": 2500,
        "x-message-ttl": 21600000,
        "x-queue-mode": "lazy",
        "x-overflow": "reject-publish",
        "x-dead-letter-exchange": "dlx-exchange",
        "x-dead-letter-routing-key": "dlx"
      }
    },
    {
      "name": "dlx-queue",
      "vhost": "/",
      "durable": true,
      "auto_delete": false,
      "arguments": {
        "x-message-ttl": 604800000,
        "x-queue-mode": "lazy"
      }
    }
  ],
  "exchanges": [
    {
      "name": "crypto-scout-exchange",
      "vhost": "/",
      "type": "direct",
      "durable": true,
      "auto_delete": false,
      "internal": false,
      "arguments": {}
    },
    {
      "name": "dlx-exchange",
      "vhost": "/",
      "type": "direct",
      "durable": true,
      "auto_delete": false,
      "internal": false,
      "arguments": {}
    }
  ],
  "bindings": [
    {
      "source": "crypto-scout-exchange",
      "vhost": "/",
      "destination": "collector-queue",
      "destination_type": "queue",
      "routing_key": "collector",
      "arguments": {}
    },
    {
      "source": "crypto-scout-exchange",
      "vhost": "/",
      "destination": "chatbot-queue",
      "destination_type": "queue",
      "routing_key": "chatbot",
      "arguments": {}
    },
    {
      "source": "crypto-scout-exchange",
      "vhost": "/",
      "destination": "analyst-queue",
      "destination_type": "queue",
      "routing_key": "analyst",
      "arguments": {}
    },
    {
      "source": "crypto-scout-exchange",
      "vhost": "/",
      "destination": "bybit-stream",
      "destination_type": "queue",
      "routing_key": "bybit",
      "arguments": {}
    },
    {
      "source": "crypto-scout-exchange",
      "vhost": "/",
      "destination": "bybit-ta-stream",
      "destination_type": "queue",
      "routing_key": "bybit-ta",
      "arguments": {}
    },
    {
      "source": "crypto-scout-exchange",
      "vhost": "/",
      "destination": "crypto-scout-stream",
      "destination_type": "queue",
      "routing_key": "crypto-scout",
      "arguments": {}
    },
    {
      "source": "dlx-exchange",
      "vhost": "/",
      "destination": "dlx-queue",
      "destination_type": "queue",
      "routing_key": "dlx",
      "arguments": {}
    }
  ]
}
```
