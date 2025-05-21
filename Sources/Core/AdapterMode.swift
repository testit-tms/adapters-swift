/// Defines the different modes the TestIt adapter can operate in.
public enum AdapterMode: Int, Codable {
    /// Filters tests based on certain criteria (e.g., from a test plan).
    case useFilter = 0

    /// Ignores any filters and runs all discovered tests.
    case runAllTests = 1

    /// Creates a new test run in TestIt, potentially ignoring existing ones.
    case newTestRun = 2

} 