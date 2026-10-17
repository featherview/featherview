import Darwin

/// This process's memory in bytes: `footprint` is what Activity Monitor shows as "Memory"; `volatile` is
/// purgeable memory marked volatile, which the footprint leaves out. Decoded images land there (seen in
/// `footprint -p`), so the footprint alone misses the cache. Both 0 if unreadable.
func memoryUse() -> (footprint: UInt64, volatile: UInt64) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? (info.phys_footprint, UInt64(max(info.ledger_purgeable_volatile, 0))) : (0, 0)
}
