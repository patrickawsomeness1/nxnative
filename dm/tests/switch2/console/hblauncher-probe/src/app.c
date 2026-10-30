/*
 * nxnative Switch 2 console-side ARM64 probe.
 *
 * This is deliberately a CPU-only HBLauncher Native SDK app. It is not a
 * retail Horizon service test and does not call NVN2. Select a stage in
 * ctx->args[1]; ctx->args[2] reports the last completed stage.
 *
 * 0: entry + ABI validation + context writeback
 * 1: host-provided stack is selected by the HBLauncher loader
 * 2: CNTVCT-backed SDK timer access
 * 3: SDK log ring write
 * 4: 64 KiB heap allocate / write / readback / free
 * 5: formatted log path
 */
#include "hbx_sdk.h"
#include "hbx_app.h"

#define NX_PROBE_MARKER 0x4e585032u /* "NXP2" */
#define NX_PROBE_BYTES  (64u * 1024u)

int hbx_app_main(const struct hbx_ctx *ctx) {
    struct hbx_ctx *out = (struct hbx_ctx *)(uintptr_t)ctx;
    const uint32_t stage = (uint32_t)ctx->args[1];
    uint32_t reached = 0;

    if (hbx_ctx_check(ctx) != HBX_OK) return HBX_ERR_ABI;
    reached = 1;

    if (stage >= 2u) {
        (void)hbx_tick();
        reached = 2;
    }

    if (stage >= 3u) {
        hbx_log(ctx, "nxnative-probe: SDK log path reached");
        reached = 3;
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
        reached = 4;
    }

    if (stage >= 5u) {
        hbx_logf(ctx, "nxnative-probe: stage=%u marker=%08x",
                 reached, NX_PROBE_MARKER);
        reached = 5;
    }

    out->frame = NX_PROBE_MARKER;
    out->args[2] = reached;
    return 0x5a;
}
