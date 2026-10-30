#include <mach/mach.h>
#include <stdint.h>

extern uint64_t nx_xom_probe_page_start(void);
extern uint64_t nx_lse_add(uint64_t *address, uint64_t value);

int nx_lse_smoke(void) {
    uint64_t value = 7;
    uint64_t previous = nx_lse_add(&value, 5);
    return previous == 7 && value == 12 ? 1 : 0;
}

// Returns 1 only when a signed __TEXT page can be remapped, reduced to execute-only,
// and executed successfully. Negative values identify the failed Mach operation.
int nx_xom_smoke(void) {
    vm_size_t page = 0;
    host_page_size(mach_host_self(), &page);
    if (page != 0x4000) return -4000 - (int)page; // nxnative's embedded sections are aligned to 16 KB
    vm_address_t alias = 0;
    vm_prot_t current = 0, maximum = 0;
    kern_return_t kr = vm_remap(
        mach_task_self(), &alias, page, 0, VM_FLAGS_ANYWHERE,
        mach_task_self(), (vm_address_t)nx_xom_probe_page_start,
        FALSE, &current, &maximum, VM_INHERIT_NONE
    );
    if (kr != KERN_SUCCESS) return -1000 - (int)kr;

    kr = vm_protect(mach_task_self(), alias, page, FALSE, VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        vm_deallocate(mach_task_self(), alias, page);
        return -2000 - (int)kr;
    }

    uint64_t (*probe)(void) = (uint64_t (*)(void))(uintptr_t)alias;
    uint64_t value = probe();
    kern_return_t cleanup = vm_deallocate(mach_task_self(), alias, page);
    if (cleanup != KERN_SUCCESS) return -3000 - (int)cleanup;
    return value == 42 ? 1 : -1;
}
