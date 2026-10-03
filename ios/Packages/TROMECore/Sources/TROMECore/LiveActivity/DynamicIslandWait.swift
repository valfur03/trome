import Foundation

public struct DynamicIslandWait: Hashable, Sendable {
    public enum Wait: Hashable, Sendable {
        case minutes(LineDirection.Train)
        case approaching
        case atPlatform
        case overAnHour
        case noTrain
        case stale
        case loading
        case noData
    }

    public enum MinimalWait: Hashable, Sendable {
        case minutes(LineDirection.Train)
        case zero
        case dash
    }

    public var line: TransitLine?
    public var wait: Wait

    init(line: TransitLine?, wait: Wait) {
        self.line = line
        self.wait = wait
    }

    public var minimalWait: MinimalWait {
        switch wait {
        case .minutes(let train): .minutes(train)
        case .approaching, .atPlatform: .zero
        case .overAnHour, .noTrain, .stale, .loading, .noData: .dash
        }
    }
}

extension StationActivityAttributes.ContentState {
    public func dynamicIslandWait(isStale: Bool) -> DynamicIslandWait {
        switch trains {
        case .loading:
            DynamicIslandWait(line: nil, wait: isStale ? .stale : .loading)
        case .noData:
            DynamicIslandWait(line: nil, wait: .noData)
        case .lines(let page):
            page.dynamicIslandWait(isStale: isStale)
        }
    }
}

private extension LinesPage {
    func dynamicIslandWait(isStale: Bool) -> DynamicIslandWait {
        if let soonest = soonestTrain {
            guard !isStale else { return DynamicIslandWait(line: soonest.line, wait: .stale) }
            let train = soonest.train ?? LineDirection.Train(time: soonest.time, destination: soonest.line.name)
            let wait: DynamicIslandWait.Wait = switch train.status {
            case .approaching: .approaching
            case .atPlatform: .atPlatform
            case nil: .minutes(train)
            }
            return DynamicIslandWait(line: soonest.line, wait: wait)
        }
        if nextTrainIsOverAnHourAway {
            return DynamicIslandWait(
                line: lineOfTheTrainOverAnHourAway ?? allLines.first,
                wait: isStale ? .stale : .overAnHour
            )
        }
        return DynamicIslandWait(line: allLines.first, wait: isStale ? .stale : .noTrain)
    }
}
