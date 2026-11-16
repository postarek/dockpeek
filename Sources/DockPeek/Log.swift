import os

/// Diagnostics: `log stream --predicate 'subsystem == "local.dockpeek"' --level info`
enum Log {
    static let app = Logger(subsystem: "local.dockpeek", category: "app")
}
