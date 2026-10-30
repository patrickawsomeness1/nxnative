// Standard Arm PAuth ELF signing-schema decoder shared by the Switch 2 loader and host probe.
#pragma once
#include <stdint.h>

static inline int nx_pauth_sign_elf_pointer(
    uint64_t value, uint64_t schema, uint64_t place, uint64_t *signed_value) {
    if (!signed_value) return 0;
    uint64_t discriminator = (schema >> 32) & 0xffff;
    unsigned key = (unsigned)((schema >> 60) & 3);
    uint64_t modifier = discriminator;
    if (schema >> 63)
        modifier = discriminator ? ((discriminator << 48) | (place & 0x0000ffffffffffffULL)) : place;
#if defined(__aarch64__) || defined(__arm64__)
    switch (key) {
    case 0: __asm__ volatile("pacia %0, %1" : "+r"(value) : "r"(modifier)); break; // APIA
    case 1: __asm__ volatile("pacib %0, %1" : "+r"(value) : "r"(modifier)); break; // APIB
    case 2: __asm__ volatile("pacda %0, %1" : "+r"(value) : "r"(modifier)); break; // APDA
    case 3: __asm__ volatile("pacdb %0, %1" : "+r"(value) : "r"(modifier)); break; // APDB
    }
    *signed_value = value;
    return 1;
#else
    (void)value; (void)modifier; (void)key; (void)schema; (void)place;
    return 0;
#endif
}
