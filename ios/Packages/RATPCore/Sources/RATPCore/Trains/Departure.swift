import Foundation

public struct Departure: Hashable, Sendable {
    public var line: TransitLine
    public var destination: String
    public var time: Date
    public var quayRef: String?
    public var directionRef: String?

    public init(
        line: TransitLine,
        destination: String,
        time: Date,
        quayRef: String? = nil,
        directionRef: String? = nil
    ) {
        self.line = line
        self.destination = destination
        self.time = time
        self.quayRef = quayRef
        self.directionRef = directionRef
    }
}
