# Goals

## Single backbone bus
- Provide exactly one dispatcher for the entire app.
- Avoid per-domain buses, implicit routing graphs, or hidden coupling.

## Strong typing with strict contracts
- Enforce that every event is Codable and Sendable.
- Ensure sinks are typed to a single concrete event type.

## Deterministic subscription rules
- Enforce exactly one sink per event type.
- Require explicit fanout via adapter sinks (no multicast by default).

## Simple, predictable delivery semantics
- Asynchronous, non-blocking dispatch.
- At-most-once delivery.
- Drop silently if no sink is registered.

## Standardized metadata via EventInfo
- Provide globally unique eventId for correlation.
- Provide monotonic timestamps for latency and ordering analysis.
- Capture call-site information (#fileID, #line, #function).
- Support low-cardinality scalar extras for domain-specific diagnostics.

## Minimal policy
- EventDispatch routes events and attaches metadata.
- Higher layers (Logger, Telme) define filtering, batching, persistence, upload, dashboards, etc.
