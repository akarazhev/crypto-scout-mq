# Issue 6: Define retention policy for streams

In this `crypto-scout-mq` project we are going to define a new `x-max-age` parameter to manage retention policy.

## Roles

Take the following roles:

- Expert dev-opts engineer.
- Expert technical writer.

## Conditions

- Use the best practices and design patterns.
- Do not hallucinate.

## Tasks

- As the expert dev-opts engineer review the current `definitions.json` config implementation in `crypto-scout-mq`
  project and
  update it by defining the `x-max-age` parameter. Define the retention policy for streams.
- As the expert dev-opts engineer recheck your proposal and make sure that they are correct and haven't missed any
  important points.
- As the technical writer update the `README.md` and `rabbitmq-production-setup.md` files with your results.
- As the technical writer update the `6-define-retention-policy-for-streams.md` file with your resolution.

---

## Resolution (2025-10-11)

- **What changed**
    - Updated `rabbitmq/definitions.json` to add time-based retention to all streams by setting `x-max-age: "1D"`
      alongside existing size-based settings.
    - Affected streams: `crypto-bybit-stream`, `metrics-bybit-stream`, `metrics-cmc-stream` under vhost `/`.
    - Resulting arguments now include: `x-max-age=1D`, `x-max-length-bytes=2000000000` (≈2GB),
      `x-stream-max-segment-size-bytes=100000000` (100MB), `x-queue-type=stream`.

- **Rationale**
    - Streams are append-only logs; without retention, disk usage grows indefinitely.
    - Combining time (`x-max-age`) and size (`x-max-length-bytes`) gives bounded growth and predictable replay horizon.
    - Explicitly pinning `x-stream-max-segment-size-bytes` ensures regular segment rollover so retention can be
      evaluated consistently.

- **Semantics and notes**
    - Retention is evaluated per segment; segments are deleted when retention criteria are met, and at least one segment
      is always kept.
    - When both `x-max-age` and `x-max-length-bytes` are set, deletion happens when both conditions are satisfied (AND
      semantics, per CloudAMQP guidance).
    - Policies can be used instead of arguments and take precedence over queue-declared values; we keep arguments in
      `definitions.json` for clarity. Operator policy can be introduced later if central control is desired.
    - Expect deletion to occur on segment rollover; continuous publishing helps trigger retention.

- **Verification**
    1) Start the service and load definitions (already configured via `rabbitmq/rabbitmq.conf: load_definitions`).
    2) Management UI → Queues → select each stream → Arguments should list `x-max-age`, `x-max-length-bytes`,
       `x-stream-max-segment-size-bytes`.
    3) Publish messages to exceed a segment and wait >1 days equivalent in a test (or temporarily reduce `x-max-age` to
       minutes) to observe segment truncation.
    4) Optional: confirm via HTTP API or `rabbitmqadmin` that arguments are present.

- **References**
    - RabbitMQ Streams docs: Data retention and per-segment behavior — https://www.rabbitmq.com/docs/streams
    - CloudAMQP guide: Streams limits & configurations (argument names, combined
      semantics) — https://www.cloudamqp.com/blog/rabbitmq-streams-and-replay-features-part-3-limits-and-configurations-for-streams-in-rabbitmq.html
    - Discussion: Retention evaluated on new segment
      creation — https://github.com/rabbitmq/rabbitmq-server/discussions/4384