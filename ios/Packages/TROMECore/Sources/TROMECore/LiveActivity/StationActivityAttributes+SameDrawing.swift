import Foundation

extension StationActivityAttributes.ContentState {
    /// Whether the Live Activity draws this content exactly as it draws `other`, so that sending it changes
    /// nothing that the rider sees. With no times to show, the time of the content is not drawn: it only counts
    /// the minutes to a train, and gives the stale date of a content that loads.
    /// Why it matters: iOS draws each update again in the widget process, and an update that comes during a draw
    /// cancels it. On a busy iPhone, where a draw can take seconds, a second update with the same look delays the
    /// new station on the lock screen by a whole draw.
    func drawsTheSame(as other: Self) -> Bool {
        guard trains == .noData, other.trains == .noData else { return self == other }
        var sameTime = other
        sameTime.updatedAt = updatedAt
        return self == sameTime
    }
}
