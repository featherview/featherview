import os

public enum Signposts {
    /// Shows in Instruments' Points of Interest and in the os_signpost instrument.
    public static let poster = OSSignposter(subsystem: "net.mynetx.featherview", category: .pointsOfInterest)
}
