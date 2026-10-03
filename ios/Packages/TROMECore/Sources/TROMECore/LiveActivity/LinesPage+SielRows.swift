extension LinesPage {
    public var sielRowsLine: LineTrains? {
        guard lines.count == 1, let line = lines.first, line.line.mode == .rer else { return nil }
        return line
    }
}
