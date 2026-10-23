import Foundation

/// Byte mutations of a valid file for fuzzing the own decoders (`featherview-bench fuzz`). Deterministic:
/// the same seed gives the same outputs, so a run can be repeated.
public struct FuzzMutator {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    /// SplitMix64.
    private mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<bound, bound > 0.
    private mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }

    /// `data` with 1–4 mutations: a bit flipped, a byte set to an edge value, 4 bytes overwritten with a
    /// size-like value, the end cut off, a run of 1–64 bytes duplicated or deleted.
    public mutating func mutate(_ data: Data) -> Data {
        var bytes = [UInt8](data)
        for _ in 0...below(4) where !bytes.isEmpty {
            let at = below(bytes.count)
            let run = 1 + below(min(64, bytes.count - at))
            switch below(6) {
            case 0: bytes[at] ^= 1 << below(8)
            case 1: bytes[at] = [0x00, 0xFF, 0x7F, 0x80][below(4)]
            case 2:
                let value = [UInt32(0xFFFF), 0x10000, 0x7FFF_FFFF][below(3)]
                let word = withUnsafeBytes(of: below(2) == 0 ? value.bigEndian : value.littleEndian, Array.init)
                let end = min(at + 4, bytes.count)
                bytes.replaceSubrange(at..<end, with: word[0..<end - at])
            case 3: bytes.removeSubrange(at...)
            case 4: bytes.insert(contentsOf: bytes[at..<at + run], at: at + run)
            default: bytes.removeSubrange(at..<at + run)
            }
        }
        return Data(bytes)
    }
}
