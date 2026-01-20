# Issue 11: Update queues, exchanges and bindings

In this `crypto-scout-mq` project we are going to update `queues`, `exchanges`, `bindings`, `routing keys`.
So let's review and update the project configuration with docs to reflect this change.

## Roles

Take the following roles:

- Expert dev-opts engineer.
- Expert technical writer.

## Conditions

- Use the best practices and design patterns.
- Do not hallucinate.
- Use the current technology stack, that's: `rabbitmq:4.1.4-management`, `podman 5.6.2`, `podman-compose 1.5.0`.
- Configuration is `rabbitmq/definitions.json`, `rabbitmq/enabled_plugins`, `rabbitmq/rabbitmq.conf`,
  `podman-compose.yml`, `secret/rabbitmq.env.example`, `secret/README.md`.

## Tasks

- As the `expert dev-opts engineer` review the current `crypto-scout-mq` project and update it by updating `queues`,
  `exchanges`, `bindings`, `routing keys` to consume crypto data and interservice communication. Rename streams:
  `crypto-bybit-stream` -> `bybit-crypto-stream`, `crypto-bybit-ta-stream` -> `bybit-ta-crypto-stream`,
  `metrics-bybit-stream` -> `bybit-parser-stream`, `metrics-cmc-stream` -> `cmc-parser-stream`.
  Define queues if they are missed: `collector-queue`, `chatbot-queue`, `analyst-queue`. Rename exchanges:
  `metrics-exchange` -> `parser-exchange`, `crypto-exchange` -> `bybit-exchange`. Define exchange:
  `crypto-scout-exchange`. Rename routing_key: `crypto-bybit` -> `bybit`, `crypto-bybit-ta` -> `bybit-ta`, 
  `metrics-bybit` -> `bybit-parser`, `metrics-cmc` -> `cmc-parser`. Define routing_keys if they are missed: `collector`, 
  `chatbot`, `analyst`.
- Recheck your proposal and make sure that they are correct and haven't missed any important points.
- As the `expert dev-opts engineer` write a report with your proposal and implementation into
  `doc/rabbitmq-production-setup.md`.
- As the `expert technical writer` update the `README.md` file to reflect the changes.
- As the `expert technical writer` write a report with your proposal and implementation into
  `doc/rabbitmq-production-setup.md`.