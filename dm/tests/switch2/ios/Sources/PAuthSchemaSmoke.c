#include <stdint.h>
#include "../../../../host/switch2/pauth.h"

extern uint64_t nx_pac_sign(uint64_t, uint64_t);
extern uint64_t nx_pac_sign_ib(uint64_t, uint64_t);
extern uint64_t nx_pac_sign_da(uint64_t, uint64_t);
extern uint64_t nx_pac_sign_db(uint64_t, uint64_t);

int nx_pauth_schema_smoke(void) {
    const uint64_t value = 0x12345678;
    const uint64_t place = 0x0000123456789000ULL;
    const uint16_t discriminators[] = {0, 0x1234};
    for (unsigned key = 0; key < 4; key++) {
        for (unsigned address_diversity = 0; address_diversity < 2; address_diversity++) {
            for (unsigned d = 0; d < 2; d++) {
                uint64_t discriminator = discriminators[d];
                uint64_t schema = ((uint64_t)key << 60) |
                    ((uint64_t)address_diversity << 63) |
                    (discriminator << 32);
                uint64_t modifier = discriminator;
                if (address_diversity)
                    modifier = discriminator
                        ? ((discriminator << 48) | (place & 0x0000ffffffffffffULL))
                        : place;
                uint64_t expected;
                switch (key) {
                case 0: expected = nx_pac_sign(value, modifier); break;
                case 1: expected = nx_pac_sign_ib(value, modifier); break;
                case 2: expected = nx_pac_sign_da(value, modifier); break;
                default: expected = nx_pac_sign_db(value, modifier); break;
                }
                uint64_t actual = 0;
                if (!nx_pauth_sign_elf_pointer(value, schema, place, &actual) ||
                    actual != expected) return 0;
            }
        }
    }
    return 1;
}
