import Foundation

public struct Departure: Codable, Hashable, Sendable {
    public var line: TransitLine
    public var destination: String
    public var time: Date
    public var quayRef: String?
    public var directionRef: String?
    public var arrivalTime: Date?
    public var isAtStop: Bool

    public init(
        line: TransitLine,
        destination: String,
        time: Date,
        quayRef: String? = nil,
        directionRef: String? = nil,
        arrivalTime: Date? = nil,
        isAtStop: Bool = false
    ) {
        self.line = line
        self.destination = destination
        self.time = time
        self.quayRef = quayRef
        self.directionRef = directionRef
        self.arrivalTime = arrivalTime
        self.isAtStop = isAtStop
    }
}
