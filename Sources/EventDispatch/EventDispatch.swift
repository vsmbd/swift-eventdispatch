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
/// Events are strongly-typed values that carry domain payload.
public protocol Event: Codable,
					   Sendable {
	//
}

// MARK: - EventInfo

/// Metadata record attached to every sunk event.
@frozen
public struct EventInfo: Sendable,
						 Hashable,
						 Codable {
	public let eventId: UInt64
	public let timestamp: MonotonicNanostamp
	public let file: String
	public let line: UInt
	public let function: String
	public let extra: [String: EventExtraValue]?

	@inlinable
	public init(
		timestamp: MonotonicNanostamp = .now,
		file: String,
		line: UInt,
		function: String,
		extra: [String: EventExtraValue]? = nil
	) {
		self.eventId = nextEventID()
		self.timestamp = timestamp
		self.file = file
		self.line = line
		self.function = function
		self.extra = extra
	}
}

// MARK: - EventExtraValue

/// Scalar value type for event metadata extras.
/// Limited to scalar types to preserve Codable and Sendable compliance.
@frozen
public enum EventExtraValue: Equatable,
							 Codable,
							 Sendable,
							 Hashable {
	case string(String)
	case bool(Bool)
	case int64(Int64)
	case uint64(UInt64)
	case double(Double)
	case float(Float)

	private enum CodingKeys: String,
							 CodingKey,
							 CaseIterable {
		case string
		case bool
		case int64
		case uint64
		case double
		case float
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		// Validate that exactly one key is present
		var foundKey: CodingKeys?
		for key in CodingKeys.allCases {
			if container.contains(key) {
				if foundKey != nil {
					throw DecodingError.dataCorrupted(
						DecodingError.Context(
							codingPath: decoder.codingPath,
							debugDescription: "EventExtraValue must contain exactly one scalar type key"
						)
					)
				}
				foundKey = key
			}
		}

		guard let key = foundKey else {
			throw DecodingError.keyNotFound(
				CodingKeys.string,
				DecodingError.Context(
					codingPath: decoder.codingPath,
					debugDescription: "EventExtraValue must contain exactly one scalar type key"
				)
			)
		}

		// Decode based on the found key
		switch key {
		case .string:
			self = .string(try container.decode(
				String.self,
				forKey: .string
			))
		case .bool:
			self = .bool(try container.decode(
				Bool.self,
				forKey: .bool
			))
		case .int64:
			self = .int64(try container.decode(
				Int64.self,
				forKey: .int64
			))
		case .uint64:
			self = .uint64(try container.decode(
				UInt64.self,
				forKey: .uint64
			))
		case .double:
			self = .double(try container.decode(
				Double.self,
				forKey: .double
			))
		case .float:
			self = .float(try container.decode(
				Float.self,
				forKey: .float
			))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		switch self {
		case let .string(value):
			try container.encode(
				value,
				forKey: .string
			)
		case let .bool(value):
			try container.encode(
				value,
				forKey: .bool
			)
		case let .int64(value):
			try container.encode(
				value,
				forKey: .int64
			)
		case let .uint64(value):
			try container.encode(
				value,
				forKey: .uint64
			)
		case let .double(value):
			try container.encode(
				value,
				forKey: .double
			)
		case let .float(value):
			try container.encode(
				value,
				forKey: .float
			)
		}
	}
}

// MARK: - AnyEvent

/// Type-erased wrapper for events to enable storage in EventDispatchEvent.
/// The original event is preserved for runtime access.
/// Note: The event itself is not encoded/decoded, only the type name is preserved for Codable.
public struct AnyEvent: Event {
	public let event: any Event
	public let eventTypeName: String

	init<E: Event>(_ event: E) {
		self.event = event
		self.eventTypeName = String(describing: E.self)
	}
}

extension AnyEvent: Codable {
	enum CodingKeys: String, CodingKey {
		case event
		case eventTypeName
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		eventTypeName = try container.decode(
			String.self,
			forKey: .eventTypeName
		)

		// We can't decode the actual event without knowing its type
		// Create a placeholder - the event won't be accessible after decoding
		// This is acceptable since EventDispatchEvent is primarily for runtime tracing
		struct PlaceholderEvent: Event {
			//
		}
		event = PlaceholderEvent()
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(
			event,
			forKey: .event
		)
		try container.encode(
			eventTypeName,
			forKey: .eventTypeName
		)
	}
}

// MARK: - EventDispatchEvent

/// Internal events emitted by EventDispatch for tracing and observability.
/// These events are only sent to the global sink, never to registered sinks.
@frozen
public enum EventDispatchEvent: Event {
	/// An event was successfully dispatched to a registered sink.
	case dispatched(
		event: AnyEvent,
		info: EventInfo
	)

	/// An event was dropped because no sink was registered for its type.
	case dropped(
		event: AnyEvent,
		info: EventInfo
	)

	/// A sink was registered for an event type.
	case sinkRegistered(
		eventType: String,
		info: EventInfo
	)

	/// A sink was unregistered for an event type.
	case sinkUnregistered(
		eventType: String,
		info: EventInfo
	)

	/// The global sink was set.
	case globalSinkSet(
		info: EventInfo
	)
}

// MARK: - EventDispatcher

/// Protocol for event dispatchers (public API for sinking events).
/// EventDispatch conforms to this protocol.
public protocol EventDispatcher: Sendable {
	/// Sinks an event with optional metadata extras.
	/// - Parameters:
	///   - event: The event to sink
	///   - extra: Optional scalar metadata dictionary
	///   - file: Call site file identifier (defaults to #fileID)
	///   - line: Call site line number (defaults to #line)
	///   - function: Call site function name (defaults to #function)
	func sink<E: Event>(
		event: E,
		extra: [String: EventExtraValue]?,
		file: StaticString,
		line: UInt,
		function: StaticString
	)
}

// MARK: - EventSink

/// Protocol for registered event sinks.
/// Sinks registered with EventDispatch must conform to this protocol.
public protocol EventSink: Sendable {
	/// Sinks an event with optional metadata extras.
	/// - Parameters:
	///   - event: The event to sink
	///   - info: The information about the event
	func sink<E: Event>(
		event: E,
		info: EventInfo
	)
}

// MARK: - EventDispatch

/// Single, app-wide, typed event router.
/// Provides exactly one dispatcher for the entire application.
public final class EventDispatch: @unchecked Sendable,
								  EventDispatcher {
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

	/// The default, app-wide EventDispatch instance.
	/// All sink operations use this instance.
	public static let `default` = EventDispatch()

	/// Sets the global sink that receives all events before registered sinks.
	/// The global sink is typically used for tracing, spanning, logging, etc.
	/// Can only be set once. Subsequent calls are ignored.
	/// - Parameters:
	///   - sink: The global sink instance
	///   - file: Call site file identifier (defaults to #fileID)
	///   - line: Call site line number (defaults to #line)
	///   - function: Call site function name (defaults to #function)
	public static func setGlobalSink(
		_ sink: any EventSink,
		file: StaticString = #fileID,
		line: UInt = #line,
		function: StaticString = #function
	) {
		_ = TaskQueue.default.sync { _ in
			guard `default`.globalSink == nil else {
				return
			}
			`default`.globalSink = sink
			// Emit event after setting to avoid recursion
			TaskQueue.default.async { taskInfo in
				let info = EventInfo(
					file: String(describing: file),
					line: line,
					function: String(describing: function),
					extra: [
						TaskQueue.TaskInfo.Key.taskId: .uint64(taskInfo.taskId)
					]
				)
				`default`.emitDispatchEvent(.globalSinkSet(info: info))
			}
		}
	}

	/// Registers a sink for a specific event type.
	/// At most one sink per event type is allowed.
	/// - Parameters:
	///   - eventType: The event type this sink handles
	///   - sink: The sink instance that handles events of the specified type
	///   - file: Call site file identifier (defaults to #fileID)
	///   - line: Call site line number (defaults to #line)
	///   - function: Call site function name (defaults to #function)
	/// - Returns: `true` if registration succeeded, `false` if a sink already exists for this event type
	@discardableResult
	public func register<E: Event>(
		_ eventType: E.Type,
		sink: any EventSink,
		file: StaticString = #fileID,
		line: UInt = #line,
		function: StaticString = #function
	) -> Bool {
		let timestamp = MonotonicNanostamp.now

		let result = TaskQueue.default.sync { _ in
			let typeID = ObjectIdentifier(E.self)

			guard sinks[typeID] == nil else {
				return false
			}

			sinks[typeID] = sink

			// Emit event after registration
			let eventTypeName = String(describing: eventType)
			TaskQueue.default.async { taskInfo in
				let info = EventInfo(
					timestamp: timestamp,
					file: String(describing: file),
					line: line,
					function: String(describing: function),
					extra: [
						TaskQueue.TaskInfo.Key.taskId: .uint64(taskInfo.taskId)
					]
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

	/// Unregisters the sink for a specific event type.
	/// - Parameters:
	///   - eventType: The event type to unregister
	///   - file: Call site file identifier (defaults to #fileID)
	///   - line: Call site line number (defaults to #line)
	///   - function: Call site function name (defaults to #function)
	/// - Returns: `true` if a sink was removed, `false` if no sink was registered for this event type
	@discardableResult
	public func unregisterSink<E: Event>(
		_ eventType: E.Type,
		file: StaticString = #fileID,
		line: UInt = #line,
		function: StaticString = #function
	) -> Bool {
		let timestamp = MonotonicNanostamp.now

		let result = TaskQueue.default.sync { _ in
			let typeID = ObjectIdentifier(E.self)
			guard sinks.removeValue(forKey: typeID) != nil else {
				return false
			}

			// Emit event after unregistration
			let eventTypeName = String(describing: eventType)
			TaskQueue.default.async { taskInfo in
				let info = EventInfo(
					timestamp: timestamp,
					file: String(describing: file),
					line: line,
					function: String(describing: function),
					extra: [
						TaskQueue.TaskInfo.Key.taskId: .uint64(taskInfo.taskId)
					]
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

	/// Sinks an event asynchronously.
	/// If no sink is registered for the event type, the event is dropped silently.
	public func sink<E: Event>(
		event: E,
		extra: [String: EventExtraValue]? = nil,
		file: StaticString = #fileID,
		line: UInt = #line,
		function: StaticString = #function
	) {
		let timestamp = MonotonicNanostamp.now
		TaskQueue.default.async { taskInfo in
			let typeID = ObjectIdentifier(E.self)

			var coorelatedExtra = extra ?? .init()
			coorelatedExtra[TaskQueue.TaskInfo.Key.taskId] = .uint64(taskInfo.taskId)

			let info = EventInfo(
				timestamp: timestamp,
				file: String(describing: file),
				line: line,
				function: String(describing: function),
				extra: coorelatedExtra
			)

			if let sink = self.sinks[typeID] {
				// Emit dispatched event with complete event and info
				// The global sink receives this EventDispatchEvent which contains the original event
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
				// Emit dropped event with complete event and info
				// The global sink receives this EventDispatchEvent which contains the original event
				self.emitDispatchEvent(.dropped(
					event: AnyEvent(event),
					info: info
				))
			}
		}
	}
}
