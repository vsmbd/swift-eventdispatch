# EventDispatch

EventDispatch is a single, app-wide, typed event router intended to act as the backbone of an application's internal communication and observability flow.

The design is intentionally strict:

- One dispatcher (`EventDispatch.default`), no per-domain buses
- One sink per event type
- Asynchronous, fire-and-forget dispatch
- Drop if no sink is registered
- Event payloads are Encodable and Sendable
- Event metadata is standardized via EventInfo (eventId, timestamp, checkpoint, taskInfo, extra)
- Global sink for cross-cutting concerns (tracing, logging, telemetry)
- Internal observability via EventDispatchEvent

EventDispatch does not attempt to be reliable messaging. It is a best-effort routing layer with predictable rules and low conceptual overhead.

## Dependencies

EventDispatch depends on **SwiftCore** for TaskQueue, Checkpoint, Entity, MonotonicNanostamp, and ScalarValue. Call-site and entity context are expressed via **Checkpoint** (entity + file/line/function); every sink and registration call takes a checkpoint for correlation.

## Core concepts

### Event

An Event is a strongly-typed value that must be:

- Encodable
- Sendable

Events carry domain payload. They do not contain routing logic. The protocol requires `kind: String` (default implementation returns the type name).

### EventDispatcher

The `EventDispatcher` protocol defines the public API for sinking events:

- `sink(_ event:_ checkpoint:extra:)` — Asynchronous event dispatch. Call-site and entity context come from `checkpoint`; optional scalar metadata in `extra` is merged into the resulting `EventInfo.extra` (with `taskId` when the call is from a TaskQueue task).

### EventSink

The `EventSink` protocol defines the interface for registered sinks. Sinks receive:

- The typed event instance
- Complete `EventInfo` metadata

EventDispatch enforces at most one registered sink per event type at any time.

If you need fanout, implement it explicitly via an adapter sink that forwards to multiple internal sinks.

### Global sink

A global sink can be set via `EventDispatch.default.setGlobalSink(_:_:)` (sink and checkpoint). It receives every event (dispatched, dropped, and internal lifecycle) before type-specific sinks. Typically used for tracing, logging, or telemetry. Can only be set once; subsequent calls are ignored.

The global sink receives events for all types, regardless of registered sinks.

### EventInfo

Every sunk event carries an `EventInfo` metadata record:

- **eventId** — Globally unique, monotonically increasing UInt64 (from EventDispatch’s native counter)
- **timestamp** — MonotonicNanostamp captured at dispatch time (before async enqueue)
- **checkpoint** — Checkpoint (entity + file/line/function) for this event; use for call-site and entity correlation
- **taskInfo** — TaskQueue.TaskInfo when the event was sunk from a TaskQueue task; nil otherwise. When present, `taskId` is also in `extra`
- **extra** — Optional scalar metadata as `[String: ScalarValue]` (SwiftCore). When `taskInfo` is present, includes `TaskInfo.Key.taskId`

Call-site details (file, line, function) are on `checkpoint`, not duplicated on EventInfo.

### EventDispatchEvent

Internal events emitted by EventDispatch for observability. Sent only to the global sink:

- **dispatched** — Event successfully routed to a registered sink
- **dropped** — Event dropped (no registered sink)
- **sinkRegistered** — A sink was registered for an event type
- **sinkUnregistered** — A sink was unregistered for an event type
- **globalSinkSet** — The global sink was set

Each `EventDispatchEvent` includes complete event and `EventInfo` instances for full traceability.

## Event lifecycle

1. Producer creates an Event value
2. Producer calls `EventDispatch.default.sink(event, checkpoint, extra:)` (e.g. checkpoint from `Checkpoint.checkpoint(self)` or `checkpoint.next(self)`)
3. EventDispatch captures timestamp (before async enqueue)
4. EventDispatch creates an `EventInfo` (eventId, timestamp, checkpoint, taskInfo, extra)
5. Event is enqueued onto `SwiftCore.TaskQueue.default` (serial)
6. On the queue:
   - Event is sent to global sink (if set)
   - If a registered sink exists for the event type, it receives the event
   - If no registered sink exists, the event is dropped silently
   - An `EventDispatchEvent` is emitted to the global sink for observability

There is no buffering, persistence, retry, acknowledgement, or backpressure.

## Threading model

- All sink invocations happen on `SwiftCore.TaskQueue.default` (serial)
- Dispatch is always asynchronous (no blocking APIs)
- Timestamps are captured synchronously before async enqueue for accuracy
- Sink registration/unregistration is synchronized via the same serial queue

## API overview

```swift
// Set global sink for tracing/logging (sink + checkpoint; call once)
let checkpoint = Checkpoint.checkpoint(self)
EventDispatch.default.setGlobalSink(myGlobalSink, checkpoint)

// Register type-specific sinks (checkpoint required)
EventDispatch.default.register(MyEvent.self, sink: mySink, checkpoint)

// Dispatch events (checkpoint required)
EventDispatch.default.sink(
    myEvent,
    Checkpoint.checkpoint(self),
    extra: ["key": .string("value")]
)

// Unregister sinks (checkpoint required)
EventDispatch.default.unregisterSink(MyEvent.self, checkpoint)
```

## Intended usage

EventDispatch is intended for:

- App-wide internal events and domain signals
- Observability/logging/telemetry pipelines (e.g. Telme) as the global sink
- Deterministic event routing without implicit fanout
- Cross-cutting concerns via global sink

It is not intended to implement guaranteed delivery, workflow engines, or distributed messaging.
