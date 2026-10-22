/// How the picture on screen differs from its decode: quarter turns clockwise, then a left–right mirror.
/// `turns` is not wrapped, so R R R animates as three clockwise turns.
public struct PictureTransform: Equatable, Sendable {
    public var mirrored: Bool
    public var turns: Int

    public init(_ changes: [OrientationChange] = []) {
        (mirrored, turns) = (false, 0)
        for change in changes {
            // Turning a mirrored picture clockwise turns the unmirrored one counter-clockwise.
            switch change {
            case .rotate(.clockwise): turns += mirrored ? -1 : 1
            case .rotate(.counterClockwise): turns += mirrored ? 1 : -1
            case .flip(.horizontal): mirrored.toggle()
            case .flip(.vertical): mirrored.toggle(); turns += 2
            }
        }
    }

    /// The EXIF orientation of the same transform.
    public var orientation: Int {
        let quarter = ((turns % 4) + 4) % 4
        return mirrored ? [2, 5, 4, 7][quarter] : [1, 6, 3, 8][quarter]
    }
}
