# Non-goals

## No reliability guarantees
- No buffering, persistence, acknowledgements, retries, or exactly-once semantics.
- Events may be dropped if no sink is registered.
- No delivery confirmation or receipt tracking.

## No backpressure management
- No queue depth limits, shedding policies, or adaptive sampling in EventDispatch v1.
- Overload detection/mitigation belongs to Telme and higher-level policy.
- No rate limiting or throttling.

## No reentrancy protection
- Sinks may dispatch additional events.
- No safeguards against recursion or pathological dispatch patterns.
- Global sink may trigger additional dispatches without protection.

## No sync dispatch
- No APIs that block waiting for a sink to handle an event.
- No request/response messaging built into the router.
- All dispatch operations are fire-and-forget.

## No implicit fanout
- Multiple sinks per event type are disallowed.
- Fanout must be implemented explicitly via adapter sinks.
- Global sink receives all events but is not considered "fanout" (it's cross-cutting).

## No untyped metadata
- No [String: Any] extras.
- Extras are limited to scalar `EventExtraValue` enum to preserve Codable and Sendable.
- No nested dictionaries or arrays in extras.

## No event transformation
- EventDispatch does not modify events.
- No filtering, mapping, or transformation capabilities.
- Events pass through unchanged.

## No sink lifecycle management
- No automatic cleanup of sinks.
- No sink health checks or monitoring.
- Sinks are responsible for their own resource management.

## No event persistence
- `AnyEvent` type-erased wrapper does not preserve event data through Codable round-trips.
- Event data is only accessible at runtime, not after decoding.
- `EventDispatchEvent` encoding loses original event payload (only type name preserved).

## No multiple EventDispatch instances
- Only `EventDispatch.default` is supported in v1.
- No factory methods or custom instances.
