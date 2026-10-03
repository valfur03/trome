import os

extension Logger {
    static let subsystem = "TROME"

    public init(category: String) {
        self.init(subsystem: Self.subsystem, category: category)
    }
}
