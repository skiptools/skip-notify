// Copyright 2023–2026 Skip
// SPDX-License-Identifier: MPL-2.0
import XCTest
import OSLog
import Foundation

let logger: Logger = Logger(subsystem: "SkipNotify", category: "Tests")

@available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
final class SkipNotifyTests: XCTestCase {
    func testSkipNotify() throws {
        logger.log("running testSkipNotify")
        XCTAssertEqual(1 + 2, 3, "basic test")
    }
}
