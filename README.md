# EventDispatch

EventDispatch is a single, app-wide, typed event router intended to act as the backbone of an application’s internal communication and observability flow.

The design is intentionally strict:

- One dispatcher (no per-domain buses)
- One sink per event type
- Asynchronous, fire-and-forget dispatch
- Drop if no sink is registered
- Event payloads are Codable and Sendable
- Event metadata is standardized via EventInfo

EventDispatch does not attempt to be reliable messaging. It is a best-effort routing layer with predictable rules and low conceptual overhead.

## Core concepts

### Event

An Event is a strongly-typed value that must be both:
- Codable
- Sendable

Events carry domain payload. They do not contain routing logic.

### Sink

A Sink is a typed subscriber for exactly one event type. EventDispatch enforces:
- at most one registered sink per event type at any time

If you need fanout, you must implement it explicitly via an adapter sink that forwards to multiple internal sinks.

### EventInfo

Every dispatched event carries an EventInfo metadata record:
- eventId: globally unique, monotonically increasing UInt64 generated atomically
- timestamp: MonotonicNanostamp captured at dispatch time
- file: #fileID of the call site
- line: source line of the call site
- function: function name of the call site
- extra: optional scalar metadata as [String: EventExtraValue]

#### EventExtraValue

EventExtraValue is a constrained scalar value type to keep metadata:
- Codable
- Sendable
- low-overhead

Scalar-only (v1): string, bool, integer, unsigned integer, double.

## Event lifecycle

1. Producer creates an Event value
2. Producer calls EventDispatch.dispatch(event, ...)
3. EventDispatch creates an EventInfo (eventId + monotonic timestamp + call-site)
4. Event is enqueued onto SwiftCore.TaskQueue.default (serial)
5. If a sink for Event.Type exists, it is invoked on the dispatcher queue
6. If no sink exists, the event is dropped silently

There is no buffering, persistence, retry, acknowledgement, or backpressure.

## Threading model

- All sink invocations happen on SwiftCore.TaskQueue.default (serial)
- Dispatch is always asynchronous
- No sync dispatch APIs are provided

## Intended usage

EventDispatch is intended for:
- app-wide internal events and domain signals
- observability/logging/telemetry pipelines (Logger, Telme)
- deterministic event routing without implicit fanout

It is not intended to implement guaranteed delivery, workflow engines, or distributed messaging.
