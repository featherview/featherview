import Foundation
import Testing

/// A settings domain name for the running test, emptied before use. The name is fixed per test because macOS
/// leaves an empty file behind for every domain even after `removePersistentDomain`: one per test, not one per run.
func testDefaultsName() -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325  // FNV-1a: stable across runs, unlike Hasher
    for byte in "\(Test.current?.id as Any)".utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
    let name = "featherview-tests-" + String(hash, radix: 16)
    UserDefaults.standard.removePersistentDomain(forName: name)
    return name
}
