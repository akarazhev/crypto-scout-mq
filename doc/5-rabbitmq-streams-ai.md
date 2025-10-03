# Context: Replacement of `metrics-bybit-queue` and `metrics-cmc-queue` with `metrics-bybit-stream` and

`metrics-cmc-stream`

In this `crypto-scout-mq` project we are going to replace `metrics-bybit-queue` and `metrics-cmc-queue` with
`metrics-bybit-stream` and `metrics-cmc-stream`. So you will need to review and update the project with docs to reflect
this change.

## Roles

Take the following roles:

- Expert dev-opts engineer.
- Expert technical writer.

## Conditions

- Use the best practices and design patterns.
- Do not hallucinate.
- Use the latest technology stack: `rabbitmq:4.1.4-management`.

## Tasks

- As the expert dev-opts engineer review the current `crypto-scout-mq` project and update by replacing
  `metrics-bybit-queue` and `metrics-cmc-queue` with `metrics-bybit-stream` and `metrics-cmc-stream`.
- Use streams for: `crypto-bybit-stream`, `metrics-bybit-stream`, `metrics-cmc-stream`.
- Delete `metrics-dead-letter-queue`.
- Use a common queue for incoming events and for messaging between services: `crypto-scout-collector-queue`.
- Recheck your proposal and make sure that they are correct and haven't missed any important points.
- As the expert dev-opts engineer write a report with your proposal and implementation into
  `doc/rabbitmq-production-setup.md`.
- As the expert technical writer update the `README.md` file to reflect the changes.
- As the expert technical writer write a report with your proposal and implementation into
  `doc/rabbitmq-production-setup.md`.