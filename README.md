# EventDispatch

EventDispatch is a single, app-wide, typed event router intended to act as the backbone of an application's internal communication and observability flow.

The design is intentionally strict:

- One dispatcher (no per-domain buses)
- One sink per event type
- Asynchronous, fire-and-forget dispatch
- Drop if no sink is registered
- Event payloads are Codable and Sendable
- Event metadata is standardized via EventInfo
- Global sink for cross-cutting concerns (tracing, logging, telemetry)
- Internal observability via EventDispatchEvent

EventDispatch does not attempt to be reliable messaging. It is a best-effort routing layer with predictable rules and low conceptual overhead.

## Core concepts

### Event

An Event is a strongly-typed value that must be both:
- Codable
- Sendable

Events carry domain payload. They do not contain routing logic.

### EventDispatcher

The `EventDispatcher` protocol defines the public API for sinking events. It provides:
- `sink(event:extra:file:line:function:)` - asynchronous event dispatch with optional metadata

### EventSink

The `EventSink` protocol defines the interface for registered sinks. Sinks receive:
- The typed event instance
- Complete `EventInfo` metadata

EventDispatch enforces at most one registered sink per event type at any time.

If you need fanout, you must implement it explicitly via an adapter sink that forwards to multiple internal sinks.

### Global Sink

A global sink can be set via `EventDispatch.setGlobalSink(_:)` to receive all events before registered sinks. The global sink is typically used for:
- Tracing and distributed tracing spans
- Logging and structured logging
- Telemetry and metrics collection

The global sink receives events for all types, regardless of registered sinks.

### EventInfo

Every sunk event carries an `EventInfo` metadata record:
- `eventId`: globally unique, monotonically increasing UInt64 generated atomically
- `timestamp`: `MonotonicNanostamp` captured at dispatch time (before async enqueue)
- `file`: `#fileID` of the call site (as String)
- `line`: source line of the call site
- `function`: function name of the call site (as String)
- `extra`: optional scalar metadata as `[String: EventExtraValue]`

#### EventExtraValue

`EventExtraValue` is a constrained scalar value type for metadata:
- Codable (uses nested JSON structure: `{"string": "value"}`, `{"uint64": 123}`, etc.)
- Sendable
- Hashable
- Low-overhead

Supported scalar types: `String`, `Bool`, `Int64`, `UInt64`, `Double`, `Float`.

The encoding uses a keyed container where the key indicates the type (e.g., `{"int64": 123}`). Exactly one type key must be present.

### EventDispatchEvent

Internal events emitted by EventDispatch for observability. These events are only sent to the global sink:
- `dispatched`: event successfully routed to a registered sink
- `dropped`: event dropped (no registered sink)
- `sinkRegistered`: a sink was registered for an event type
- `sinkUnregistered`: a sink was unregistered for an event type
- `globalSinkSet`: the global sink was set

Each `EventDispatchEvent` includes complete event and `EventInfo` instances for full traceability.

## Event lifecycle

1. Producer creates an Event value
2. Producer calls `EventDispatch.default.sink(event:extra:file:line:function:)`
3. EventDispatch captures timestamp (before async enqueue)
4. EventDispatch creates an `EventInfo` (eventId + timestamp + call-site + extras)
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
// Set global sink for tracing/logging
EventDispatch.setGlobalSink(myGlobalSink)

// Register type-specific sinks
EventDispatch.default.register(MyEvent.self, sink: mySink)

// Dispatch events
EventDispatch.default.sink(
    event: MyEvent(...),
    extra: ["key": .string("value")]
)

// Unregister sinks
EventDispatch.default.unregisterSink(MyEvent.self)
```

## Intended usage

EventDispatch is intended for:
- App-wide internal events and domain signals
- Observability/logging/telemetry pipelines (Logger, Telme)
- Deterministic event routing without implicit fanout
- Cross-cutting concerns via global sink

It is not intended to implement guaranteed delivery, workflow engines, or distributed messaging.
