/*
 * nxnative Switch 2 console-side ARM64 probe.
 *
 * This is deliberately a CPU-only HBLauncher Native SDK app. It is not a
 * retail Horizon service test and does not call NVN2. Select a stage in
 * ctx->args[1]; ctx->args[2] reports the last completed stage.
 *
 * 0: entry + ABI validation + context writeback
 * 1: loader-provided stack pointer is nonzero and 16-byte aligned
 * 2: CNTFRQ_EL0 + CNTVCT_EL0 timer frequency/sample capture
 * 3: SDK log ring write
 * 4: 64 KiB heap allocate / write / readback / free
 * 5: formatted log path
 * 6: PACIA/IB/DA/DB authentication round trips
 * 7: PAC-authenticated BRAA branch into a BTI landing pad
 * 8: LSE LDADDAL atomic read/modify/write
 */
#include "hbx_sdk.h"
#include "hbx_app.h"
#include <stdint.h>

extern int nx_probe_pac_keys(void);
extern int nx_probe_pac_branch(void);
extern uint64_t nx_probe_lse_add(volatile uint64_t *address, uint64_t value);

#define NX_PROBE_MARKER 0x4e585032u /* "NXP2" */
#define NX_PROBE_BYTES  (64u * 1024u)

int hbx_app_main(const struct hbx_ctx *ctx) {
    struct hbx_ctx *out = (struct hbx_ctx *)(uintptr_t)ctx;
    const uint32_t requested_stage = (uint32_t)ctx->args[1];
    const uint32_t stage = requested_stage ? requested_stage : 8u; /* default: run every stage */
    uint32_t reached = 0;

    if (hbx_ctx_check(ctx) != HBX_OK) return HBX_ERR_ABI;
    reached = 1;

    if (stage >= 1u) {
        uintptr_t stack_pointer;
        __asm__ volatile("mov %0, sp" : "=r"(stack_pointer));
        if (!stack_pointer || (stack_pointer & 15u)) return HBX_ERR_ABI;
        reached = 2;
    }

    if (stage >= 2u) {
        uint64_t before = hbx_tick();       /* HBLauncher SDK: GetSystemTick, SVC #0x1e */
        hbx_sleep_ns(1000000u);             /* SleepThread, SVC #0x0b */
        uint64_t after = hbx_tick();
        if (!ctx->tick_hz || after <= before) return HBX_ERR_TIMEOUT;
        out->args[3] = ctx->tick_hz;
        out->args[4] = before;
        out->args[5] = after - before;
        reached = 3;
    }

    if (stage >= 3u) {
        hbx_log(ctx, "nxnative-probe: SDK log path reached");
        reached = 4;
    }

    if (stage >= 4u) {
        struct hbx_heap heap;
        uint8_t *block;
        uint32_t i;
        uint32_t checksum = 0;

        hbx_heap_init(&heap, (void *)(uintptr_t)ctx->heap_base, ctx->heap_size);
        block = (uint8_t *)hbx_alloc(&heap, NX_PROBE_BYTES);
        if (!block) return HBX_ERR_HEAP;

        for (i = 0; i < NX_PROBE_BYTES; ++i)
            block[i] = (uint8_t)((i * 37u) ^ (i >> 3));
        for (i = 0; i < NX_PROBE_BYTES; ++i)
            checksum += block[i];

        hbx_free(&heap, block);
        if (checksum == 0u) return HBX_ERR_INTERNAL;
        reached = 5;
    }

    if (stage >= 5u) {
        hbx_logf(ctx, "nxnative-probe: stage=%u marker=%08x",
                 reached, NX_PROBE_MARKER);
        reached = 6;
    }

    if (stage >= 6u) {
        if (!nx_probe_pac_keys()) return HBX_ERR_UNSUPPORTED;
        reached = 7;
    }

    if (stage >= 7u) {
        if (nx_probe_pac_branch() != 42) return HBX_ERR_UNSUPPORTED;
        reached = 8;
    }

    if (stage >= 8u) {
        volatile uint64_t atomic_value = 0x10;
        uint64_t previous = nx_probe_lse_add(&atomic_value, 0x5);
        if (previous != 0x10 || atomic_value != 0x15) return HBX_ERR_UNSUPPORTED;
        reached = 9;
    }

    out->frame = NX_PROBE_MARKER;
    out->args[2] = reached;
    return HBX_OK;
}
