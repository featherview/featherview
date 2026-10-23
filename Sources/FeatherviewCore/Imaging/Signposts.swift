import os

public enum Signposts {
    /// Shows in Instruments' Points of Interest and in the os_signpost instrument.
    public static let poster = OSSignposter(subsystem: "net.mynetx.featherview", category: .pointsOfInterest)
}

extension Duration {
    /// For timing logs and the bench.
    public var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}
