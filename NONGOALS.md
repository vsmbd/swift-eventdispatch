# Non-goals

## No reliability guarantees
- No buffering, persistence, acknowledgements, retries, or exactly-once semantics.
- Events may be dropped if no sink is registered.

## No backpressure management
- No queue depth limits, shedding policies, or adaptive sampling in EventDispatch v1.
- Overload detection/mitigation belongs to Telme and higher-level policy.

## No reentrancy protection
- Sinks may dispatch additional events.
- No safeguards against recursion or pathological dispatch patterns.

## No sync dispatch
- No APIs that block waiting for a sink to handle an event.
- No request/response messaging built into the router.

## No implicit fanout
- Multiple sinks per event type are disallowed.
- Fanout must be implemented explicitly via adapter sinks.

## No untyped metadata
- No [String: Any] extras.
- Extras are limited to scalar EventExtraValue to preserve Codable and Sendable.
