import Foundation
import Testing
@testable import FeatherviewCore

@Suite struct FuzzMutatorTests {
    static let input = Data((0..<256).map { UInt8($0) })

    @Test func sameSeedSameOutput() {
        var a = FuzzMutator(seed: 7), b = FuzzMutator(seed: 7)
        for _ in 0..<100 { #expect(a.mutate(Self.input) == b.mutate(Self.input)) }
    }

    @Test func mutatesSomething() {
        var mutator = FuzzMutator(seed: 1)
        let changed = (0..<100).filter { _ in mutator.mutate(Self.input) != Self.input }.count
        #expect(changed >= 95)
    }

    @Test func emptyInputStaysUsable() {
        var mutator = FuzzMutator(seed: 3)
        for _ in 0..<20 { _ = mutator.mutate(Data()) }
        for _ in 0..<20 { _ = mutator.mutate(Data([1])) }
    }
}
