/*
 * nxnative Switch 2 console-side ARM64 probe.
 *
 * This is deliberately a CPU-only HBLauncher Native SDK app. It is not a
 * retail Horizon service test and does not call NVN2. Select a stage in
 * ctx->args[1]; ctx->args[2] reports the last completed stage.
 *
 * 0: entry + ABI validation + context writeback
 * 1: loader-provided stack pointer is nonzero and 16-byte aligned
 * 2: GetSystemTick (SVC 0x1e) + SleepThread (SVC 0x0b) timer round trip
 * 3: SDK log ring write
 * 4: 64 KiB heap allocate / write / readback / free
 * 5: formatted log path
 * 6: PACIA/IB/DA/DB authentication round trips
 * 7: PAC-authenticated BRAA branch into a BTI landing pad
 * 8: LSE LDADDAL atomic read/modify/write
 * 9: experimental sm:RegisterClient CMIF request via ConnectToNamedPort/SendSyncRequest
 */
#include "hbx_sdk.h"
#include "hbx_app.h"
#include <stdint.h>
#include <string.h>

extern int nx_probe_pac_keys(void);
extern int nx_probe_pac_branch(void);
extern uint64_t nx_probe_lse_add(volatile uint64_t *address, uint64_t value);
extern uint32_t nx_probe_connect_to_named_port(uint32_t *handle, const char *name);
extern uint32_t nx_probe_send_sync_request(uint32_t handle);
extern uint32_t nx_probe_close_handle(uint32_t handle);

#define NX_PROBE_MARKER 0x4e585032u /* "NXP2" */

static uint32_t nx_probe_read_le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void nx_probe_write_le32(uint8_t *p, uint32_t value) {
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
    p[2] = (uint8_t)(value >> 16);
    p[3] = (uint8_t)(value >> 24);
}

// Exercise the standard sm:RegisterClient CMIF v0 request. SVC numbers
// 0x1f/0x21/0x16 are reference ABI candidates and must be verified on Switch 2.
static uint32_t nx_probe_sm_register_client(void) {
    uint32_t handle = 0;
    uint32_t result = nx_probe_connect_to_named_port(&handle, "sm:");
    if (result) return result;

    uint8_t *tls = NULL;
    __asm__ volatile("mrs %0, tpidrro_el0" : "=r"(tls));
    if (!tls) {
        (void)nx_probe_close_handle(handle);
        return HBX_ERR_ABI;
    }

    // armGetTls() is TPIDRRO_EL0. Only clear the 60-byte IPC message area;
    // the rest of the thread-local region contains live runtime state.
    memset(tls, 0, 60);
    nx_probe_write_le32(tls, 4u | (1u << 31));       // HIPC Request + special header.
    nx_probe_write_le32(tls + 4, 10u | (1u << 31)); // 10 data words + special header.
    nx_probe_write_le32(tls + 8, 1u);               // send_pid; kernel fills the PID slot.
    nx_probe_write_le32(tls + 32, 0x49434653u);     // SFCI
    nx_probe_write_le32(tls + 36, 0u);              // CMIF v0
    nx_probe_write_le32(tls + 40, 0u);              // RegisterClient command ID
    nx_probe_write_le32(tls + 44, 0u);              // token
    // tls[48..55] is the u64 PID placeholder; it remains zero.

    result = nx_probe_send_sync_request(handle);
    if (result == 0) {
        const uint32_t hipc_type = nx_probe_read_le32(tls);
        const uint32_t data_words = nx_probe_read_le32(tls + 4) & 0x3ffu;
        const uint32_t sfco = nx_probe_read_le32(tls + 16);
        const uint32_t version = nx_probe_read_le32(tls + 20);
        const uint32_t cmif_result = nx_probe_read_le32(tls + 24);
        if (hipc_type != 0u || data_words < 6u ||
            sfco != 0x4f434653u || version != 0u)
            result = HBX_ERR_ABI;
        else
            result = cmif_result;
    }

    const uint32_t close_result = nx_probe_close_handle(handle);
    if (result == 0) result = close_result;
    return result;
}
#define NX_PROBE_BYTES  (64u * 1024u)

int hbx_app_main(const struct hbx_ctx *ctx) {
    struct hbx_ctx *out = (struct hbx_ctx *)(uintptr_t)ctx;
    const uint32_t requested_stage = (uint32_t)ctx->args[1];
    const uint32_t stage = requested_stage ? requested_stage : 9u; /* default: run every stage */
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

    if (stage >= 9u) {
        out->args[6] = nx_probe_sm_register_client();
        if (out->args[6] == 0) reached = 10;
    }

    out->frame = NX_PROBE_MARKER;
    out->args[2] = reached;
    return HBX_OK;
}
