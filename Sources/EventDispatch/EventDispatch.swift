//
//  EventDispatch.swift
//  swift-eventdispatch
//
//  Created by vsmbd on 26/01/26.
//

import SwiftCore
import EventDispatchNativeCounters

// MARK: - Event

/// Protocol that all events must conform to.
/// Events are strongly-typed, domain payload values. They are routed by type; at most one sink per event type is registered. Events must be `Encodable` and `Sendable` for safe serialization and cross-thread use.
public protocol Event: Encodable,
					   Sendable {
	var kind: String { get }
}

extension Event {
	@inlinable
	public var typeName: String {
		String(describing: type(of: self))
	}

	@inlinable
	public var kind: String {
		typeName
	}
}

// MARK: - EventInfo

/// Metadata record attached to every sunk event. Carries identity (eventId), time (timestamp), call-site and entity context (checkpoint), optional task context (taskInfo), and scalar extras.
/// Call-site details (file, line, function) are on `checkpoint`.
@frozen
public struct EventInfo: Sendable,
						 Hashable,
						 Encodable {
	/// Globally unique event id (process-wide, from native counter).
	public let eventId: UInt64
	/// Monotonic timestamp captured when the event was sunk (before async enqueue).
	public let timestamp: MonotonicNanostamp
	/// Checkpoint (entity + file/line/function) for this event. Use for call-site and entity correlation.
	public let checkpoint: Checkpoint
	/// Task info when the event was sunk from a TaskQueue task; `nil` otherwise. When non-nil, `taskId` is also in `extra`.
	public let taskInfo: TaskQueue.TaskInfo?
	/// Optional scalar metadata. When `taskInfo` is present, includes `TaskQueue.TaskInfo.Key.taskId`.
	public let extra: [String: ScalarValue]?

	/// Creates event metadata. When `taskInfo` is non-nil, merges `taskId` into `extra` (creating or updating the dictionary).
	/// - Parameters:
	///   - timestamp: Monotonic time for the event; defaults to `.now`.
	///   - checkpoint: Checkpoint (entity + file/line/function) for this event.
	///   - taskInfo: Optional task context; when present, `taskId` is added to `extra`.
	///   - extra: Optional scalar metadata; merged with `taskId` when `taskInfo` is non-nil.
	@inlinable
	public init(
		timestamp: MonotonicNanostamp = .now,
		checkpoint: Checkpoint,
		taskInfo: TaskQueue.TaskInfo? = nil,
		extra: [String: ScalarValue]? = nil
	) {
		self.eventId = nextEventID()
		self.timestamp = timestamp
		self.checkpoint = checkpoint
		self.taskInfo = taskInfo
		self.extra = extra
	}
}

// MARK: - AnyEvent

/// Type-erased wrapper for events so they can be stored and passed as a single type (e.g. in `EventDispatchEvent`).
/// The original event is available at runtime via `event`; `eventTypeName` identifies the type. When decoding, the payload is replaced by a placeholder—only `eventTypeName` is preserved.
public struct AnyEvent: Event {
	/// The type-erased event instance. After decoding, this is a placeholder if the event was encoded.
	public let event: any Event

	@inlinable
	public var kind: String {
		event.kind
	}

	public init<E: Event>(_ event: E) {
		self.event = event
	}
}

extension AnyEvent: Encodable {
	enum CodingKeys: String,
					 CodingKey {
		case event
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(
			event,
			forKey: .event
		)
	}
}

// MARK: - EventDispatchEvent

/// Internal events emitted by EventDispatch for tracing and observability. Sent only to the global sink (if set), never to type-specific registered sinks. Use to observe dispatch, drops, and registration lifecycle.
@frozen
public enum EventDispatchEvent: Event {
	/// A domain event was successfully dispatched to a registered sink for its type.
	case dispatched(
		event: AnyEvent,
		info: EventInfo
	)

	/// A domain event was dropped because no sink was registered for its type.
	case dropped(
		event: AnyEvent,
		info: EventInfo
	)

	/// A sink was registered for an event type. `eventType` is the type name (e.g. `String(describing: E.self)`).
	case sinkRegistered(
		eventType: String,
		info: EventInfo
	)

	/// A sink was unregistered for an event type.
	case sinkUnregistered(
		eventType: String,
		info: EventInfo
	)

	/// The global sink was set. Emitted asynchronously after the set call.
	case globalSinkSet(
		info: EventInfo
	)

	public var kind: String {
		switch self {
		case .dispatched:
			typeName + "_dispatched"

		case .dropped:
			typeName + "_dropped"

		case .sinkRegistered:
			typeName + "_sinkRegistered"

		case .sinkUnregistered:
			typeName + "_sinkUnregistered"

		case .globalSinkSet:
			typeName + "_globalSinkSet"
		}
	}
}

// MARK: - EventDispatcher

/// Protocol for event dispatchers (public API for sinking events). `EventDispatch.default` conforms. Callers supply a checkpoint (entity + call site) so every sunk event is correlated to an origin.
public protocol EventDispatcher: Sendable {
	/// Sinks an event asynchronously. Call-site and entity context come from `checkpoint`; optional scalar metadata in `extra` is merged into the resulting `EventInfo.extra` (with `taskId` when the call is from a task).
	/// - Parameters:
	///   - event: The event to sink.
	///   - checkpoint: Checkpoint (entity + file/line/function) for this sink call; use e.g. `Checkpoint.at(self, ...)` or a successor from another checkpoint.
	///   - extra: Optional scalar key-value metadata attached to the event’s `EventInfo`.
	func sink<E: Event>(
		_ event: E,
		_ checkpoint: Checkpoint,
		extra: [String: ScalarValue]?
	)
}

// MARK: - EventSink

/// Protocol for sinks that receive events. Implement this for type-specific sinks registered with `EventDispatch.register(_:sink:checkpoint:)` or for the global sink set with `EventDispatch.setGlobalSink(_:checkpoint:)`. Sinks are invoked on the default TaskQueue; implement thread-safe ingestion if needed.
public protocol EventSink: Sendable {
	/// Receives a sunk event and its metadata. Called on the default TaskQueue.
	/// - Parameters:
	///   - event: The typed event instance.
	///   - info: Event metadata (eventId, timestamp, checkpoint, taskInfo, extra).
	func sink<E: Event>(
		event: E,
		info: EventInfo
	)
}

// MARK: - EventDispatch

/// Single, app-wide, typed event router. Provides one dispatcher instance (`EventDispatch.default`) for the entire app. Routes events by type to at most one registered sink per type; supports a global sink for all events (tracing, logging). Conforms to `Entity` so checkpoint chains can identify EventDispatch as the origin. All work runs on `TaskQueue.default`; callers pass a checkpoint for correlation.
public final class EventDispatch: @unchecked Sendable,
								  EventDispatcher,
								  Entity {
	// MARK: + Private scope

	private var globalSink: (any EventSink)?
	private var sinks: [ObjectIdentifier: any EventSink] = [:]

	/// Emits an EventDispatchEvent to the global sink only.
	/// Used for internal tracing and observability.
	private func emitDispatchEvent(_ dispatchEvent: EventDispatchEvent) {
		guard let globalSink = globalSink else {
			return
		}

		// Extract EventInfo from the dispatch event
		let info: EventInfo
		switch dispatchEvent {
		case let .dispatched(_, eventInfo),
			 let .dropped(_, eventInfo),
			 let .sinkRegistered(_, eventInfo),
			 let .sinkUnregistered(_, eventInfo),
			 let .globalSinkSet(eventInfo):
			info = eventInfo
		}

		globalSink.sink(
			event: dispatchEvent,
			info: info
		)
	}

	private init() {
		//
	}

	// MARK: + Public scope

	/// The default, app-wide EventDispatch instance. Use this for all sink, register, and unregister calls.
	public static let `default` = EventDispatch()

	/// Sets the global sink that receives every event (dispatched, dropped, and internal lifecycle) before type-specific sinks. Typically used for tracing, logging, or telemetry. Can only be set once; subsequent calls are ignored.
	/// - Parameters:
	///   - sink: The sink that will receive all events.
	///   - checkpoint: Checkpoint (entity + call site) for this call; used to enqueue the globalSinkSet notification.
	public func setGlobalSink(
		_ sink: any EventSink,
		_ checkpoint: Checkpoint
	) {
		guard globalSink == nil else {
			return
		}
		globalSink = sink

		TaskQueue.default.async(checkpoint.next(self)) { [weak self] taskInfo in
			guard let self else { return }

			let info = EventInfo(
				checkpoint: taskInfo.checkpoint.next(self),
				taskInfo: taskInfo
			)
			emitDispatchEvent(.globalSinkSet(info: info))
		}
	}

	/// Registers a sink for an event type. At most one sink per event type; registration is synchronized on the default TaskQueue.
	/// - Parameters:
	///   - eventType: The event type (e.g. `MyEvent.self`) this sink handles.
	///   - sink: The sink that will receive events of this type.
	///   - checkpoint: Checkpoint (entity + call site) for this call.
	/// - Returns: `true` if the sink was registered, `false` if a sink was already registered for this type.
	@discardableResult
	public func register<E: Event>(
		_ eventType: E.Type,
		sink: any EventSink,
		checkpoint: Checkpoint
	) -> Bool {
		let timestamp = MonotonicNanostamp.now

		let result = TaskQueue.default.sync(checkpoint.next(self)) { syncTaskInfo in
			let typeID = ObjectIdentifier(E.self)

			guard sinks[typeID] == nil else {
				return false
			}

			sinks[typeID] = sink

			// Emit event after registration
			let eventTypeName = String(describing: eventType)
			TaskQueue.default
				.async(syncTaskInfo.checkpoint.next(self)) { taskInfo in
				let info = EventInfo(
					timestamp: timestamp,
					checkpoint: taskInfo.checkpoint.next(self),
					taskInfo: taskInfo
				)
				self.emitDispatchEvent(.sinkRegistered(
					eventType: eventTypeName,
					info: info
				))
			}

			return true
		}

		return result.value
	}

	/// Unregisters the sink for an event type. Synchronized on the default TaskQueue.
	/// - Parameters:
	///   - eventType: The event type (e.g. `MyEvent.self`) to unregister.
	///   - checkpoint: Checkpoint (entity + call site) for this call.
	/// - Returns: `true` if a sink was removed, `false` if none was registered for this type.
	@discardableResult
	public func unregisterSink<E: Event>(
		_ eventType: E.Type,
		checkpoint: Checkpoint
	) -> Bool {
		let timestamp = MonotonicNanostamp.now

		let result = TaskQueue.default.sync(checkpoint.next(self)) { syncTaskInfo in
			let typeID = ObjectIdentifier(E.self)
			guard sinks.removeValue(forKey: typeID) != nil else {
				return false
			}

			// Emit event after unregistration
			let eventTypeName = String(describing: eventType)
			TaskQueue.default
				.async(syncTaskInfo.checkpoint.next(self)) { taskInfo in
				let info = EventInfo(
					timestamp: timestamp,
					checkpoint: taskInfo.checkpoint.next(self),
					taskInfo: taskInfo
				)
				self.emitDispatchEvent(.sinkUnregistered(
					eventType: eventTypeName,
					info: info
				))
			}

			return true
		}

		return result.value
	}

	/// Sinks an event asynchronously on the default TaskQueue. If a sink is registered for the event’s type, it receives the event; otherwise the event is dropped and a dropped event is emitted to the global sink. Timestamp is captured before enqueue.
	/// - Parameters:
	///   - event: The event to sink.
	///   - checkpoint: Checkpoint (entity + call site) for this call.
	///   - extra: Optional scalar metadata merged into the event’s `EventInfo.extra` (with `taskId` when run from a task).
	public func sink<E: Event>(
		_ event: E,
		_ checkpoint: Checkpoint,
		extra: [String: ScalarValue]? = nil
	) {
		let timestamp = MonotonicNanostamp.now
		TaskQueue.default.async(checkpoint.next(self)) { taskInfo in
			let typeID = ObjectIdentifier(E.self)

			let info = EventInfo(
				timestamp: timestamp,
				checkpoint: taskInfo.checkpoint.next(self),
				taskInfo: taskInfo
			)

			if let sink = self.sinks[typeID] {
				// Emit dispatched event
				self.emitDispatchEvent(.dispatched(
					event: AnyEvent(event),
					info: info
				))

				// Send to registered sink for this event type
				sink.sink(
					event: event,
					info: info
				)
			} else {
				// Emit dropped event
				self.emitDispatchEvent(.dropped(
					event: AnyEvent(event),
					info: info
				))
			}
		}
	}
}
