# EventDispatch Goals

This document defines what EventDispatch must achieve.

## Single backbone bus

- Provide exactly one dispatcher (`EventDispatch.default`) for the entire app.
- Avoid per-domain buses, implicit routing graphs, or hidden coupling.
- Singleton pattern ensures consistent routing behavior.

## Strong typing with strict contracts

- Enforce that every event is Encodable and Sendable.
- Separate `EventDispatcher` (public API for sinking) from `EventSink` (receiver interface).
- Type-based routing using `ObjectIdentifier` for deterministic matching.
- Event protocol requires `kind: String` (default: type name).

## Checkpoint-based correlation

- Every sink and registration call takes a **Checkpoint** (entity + file/line/function from SwiftCore).
- EventInfo carries checkpoint (and optional taskInfo) so all events are correlated to an origin and call site.
- EventDispatch conforms to Entity so checkpoint chains can identify it as the origin.

## Deterministic subscription rules

- Enforce exactly one sink per event type.
- Require explicit fanout via adapter sinks (no multicast by default).
- Registration/unregistration returns boolean indicating success.

## Simple, predictable delivery semantics

- Asynchronous, non-blocking dispatch via `sink(_:_:extra:)` (event, checkpoint, extra).
- At-most-once delivery.
- Drop silently if no sink is registered.
- No sync dispatch APIs.

## Standardized metadata via EventInfo

- Globally unique `eventId` (UInt64) from EventDispatch’s native counter (EventDispatchNativeCounters).
- Monotonic timestamp (`MonotonicNanostamp`) captured at dispatch time (before async enqueue).
- Call-site and entity context via **checkpoint** (SwiftCore.Checkpoint).
- Optional task context via **taskInfo** (TaskQueue.TaskInfo) when sunk from a task; `taskId` merged into `extra`.
- Low-cardinality scalar extras via SwiftCore **ScalarValue** (`[String: ScalarValue]`).

## Global sink for cross-cutting concerns

- Global sink receives all events before type-specific sinks.
- Set once via `EventDispatch.default.setGlobalSink(_:_:)` (sink and checkpoint).
- Enables tracing, logging, telemetry without per-type registration.

## Internal observability

- Emit `EventDispatchEvent` to global sink for all internal operations (dispatched, dropped, sinkRegistered, sinkUnregistered, globalSinkSet).
- Events include complete event instances and `EventInfo` for full traceability.

## Minimal policy

- EventDispatch routes events and attaches metadata.
- Higher layers (e.g. Telme) define filtering, batching, persistence, upload, dashboards.
- No event transformation, filtering, or policy decisions in EventDispatch.
