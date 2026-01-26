# Goals

## Single backbone bus
- Provide exactly one dispatcher (`EventDispatch.default`) for the entire app.
- Avoid per-domain buses, implicit routing graphs, or hidden coupling.
- Singleton pattern ensures consistent routing behavior.

## Strong typing with strict contracts
- Enforce that every event is Codable and Sendable.
- Separate `EventDispatcher` (public API) from `EventSink` (registration API).
- Type-based routing using `ObjectIdentifier` for deterministic matching.

## Deterministic subscription rules
- Enforce exactly one sink per event type.
- Require explicit fanout via adapter sinks (no multicast by default).
- Registration/unregistration returns boolean indicating success.

## Simple, predictable delivery semantics
- Asynchronous, non-blocking dispatch via `sink(event:extra:file:line:function:)`.
- At-most-once delivery.
- Drop silently if no sink is registered.
- No sync dispatch APIs.

## Standardized metadata via EventInfo
- Provide globally unique `eventId` (UInt64) generated atomically via `nextEventID()`.
- Provide monotonic timestamps (`MonotonicNanostamp`) captured at dispatch time (before async enqueue).
- Capture call-site information (`#fileID`, `#line`, `#function`) for all operations.
- Support low-cardinality scalar extras via `EventExtraValue` enum.
- `EventExtraValue` uses nested JSON structure for type disambiguation.

## Global sink for cross-cutting concerns
- Provide a global sink that receives all events before registered sinks.
- Global sink is set once via `EventDispatch.setGlobalSink(_:)`.
- Enables tracing, logging, telemetry without per-type registration.

## Internal observability
- Emit `EventDispatchEvent` to global sink for all internal operations.
- Events include complete event instances and `EventInfo` for full traceability.
- Supports honest tracing of dispatch, drops, registrations, and unregistrations.

## Minimal policy
- EventDispatch routes events and attaches metadata.
- Higher layers (Logger, Telme) define filtering, batching, persistence, upload, dashboards, etc.
- No event transformation, filtering, or policy decisions in EventDispatch.
