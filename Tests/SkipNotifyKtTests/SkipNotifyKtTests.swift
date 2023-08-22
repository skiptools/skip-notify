import SkipUnit

/// This test case will run the transpiled tests for the Skip module.
@available(macOS 13, macCatalyst 16, *)
final class SkipFoundationKtTests: XCTestCase, XCGradleHarness {
    /// This test case will run the transpiled tests defined in the Swift peer module.
    /// New tests should be added there, not here.
    public func testSkipModule() async throws {
        try await gradle(actions: ["testDebug"])
    }
}
