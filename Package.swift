// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "EventDispatch",
	products: [
		.library(
			name: "EventDispatch",
			targets: ["EventDispatch"]
		)
	],
	dependencies: [
		.package(
			url: "https://github.com/vsmbd/swift-core.git",
			branch: "main"
		)
	],
	targets: [
		.target(
			name: "EventDispatch",
			dependencies: [
				"EventDispatchNativeCounters",
				.product(
					name: "SwiftCore",
					package: "swift-core"
				)
			],
			path: "Sources/EventDispatch"
		),
		.target(
			name: "EventDispatchNativeCounters",
			path: "Sources/EventDispatchNativeCounters",
			publicHeadersPath: "include"
		),
		.testTarget(
			name: "EventDispatchTests",
			dependencies: ["EventDispatch"],
			path: "Tests/EventDispatchTests"
		)
	]
)
