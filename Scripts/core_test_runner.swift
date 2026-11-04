import Foundation

@main
private struct CoreTestRunner {
    static func main() async throws {
        try CoreTestSupport.runLegacySuite()
        try await CoreTestSupport.runPasteFocusValidation()
        print("All cpsmart core tests passed.")
    }
}
