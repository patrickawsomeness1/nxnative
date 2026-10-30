/*
 * nxnative Switch 2 console-side bring-up probe.
 *
 * Built against the public HBLauncher Native SDK ABI v3. It is a homebrew
 * diagnostic package for the HBLauncher userland environment, not an NRO,
 * not an NVN2 implementation, and not a commercial-game loader.
 */
#include "hbx_sdk.h"
#include "hbx_app.h"
#include "hbx_ui.h"

static void append_text(char *out, unsigned *used, const char *text) {
    while (*text && *used < 120u) out[(*used)++] = *text++;
    out[*used] = 0;
}

static void append_u64(char *out, unsigned *used, uint64_t value) {
    char digits[24];
    unsigned count = 0;
    do {
        digits[count++] = (char)('0' + (value % 10u));
        value /= 10u;
    } while (value && count < sizeof digits);
    while (count && *used < 120u) out[(*used)++] = digits[--count];
    out[*used] = 0;
}

static int heap_smoke_test(const struct hbx_ctx *ctx, uint64_t *peak) {
    struct hbx_heap heap;
    uint32_t *memory;
    uint32_t i;
    const uint32_t words = 16384u; /* 64 KiB */
    hbx_heap_init(&heap, (void *)(uintptr_t)ctx->heap_base, ctx->heap_size);
    memory = (uint32_t *)hbx_alloc(&heap, (uint64_t)words * sizeof(uint32_t));
    if (!memory) return 0;
    for (i = 0; i < words; i++) memory[i] = (i * 2654435761u) ^ 0x5357324eu;
    for (i = 0; i < words; i++) {
        if (memory[i] != ((i * 2654435761u) ^ 0x5357324eu)) {
            hbx_free(&heap, memory);
            return 0;
        }
    }
    *peak = hbx_heap_peak(&heap);
    hbx_free(&heap, memory);
    return 1;
}

int hbx_app_main(const struct hbx_ctx *ctx) {
    struct hbx_input_state input;
    struct hbx_heap heap;
    uint64_t heap_peak = 0;
    uint64_t started;
    uint64_t deadline = 0;
    uint32_t frame = 0;
    int heap_ok;
    int ui_ok;
    char line[128];
    unsigned used;

    if (hbx_ctx_check(ctx) != HBX_OK) return HBX_ERR_ABI;
    hbx_memset(&input, 0, sizeof input);
    hbx_heap_init(&heap, (void *)(uintptr_t)ctx->heap_base, ctx->heap_size);
    heap_ok = heap_smoke_test(ctx, &heap_peak);
    ui_ok = hbx_ui_available(ctx);
    started = hbx_now_ns(ctx);

    hbx_log(ctx, "nxnative-switch2-probe: HBLauncher ABI v3 entry");
    hbx_logf(ctx, "nxnative-switch2-probe: gpu=%ux%u images=%u queue_family=%u",
             ctx->gpu.width, ctx->gpu.height, ctx->gpu.image_count, ctx->gpu.queue_family);
    hbx_logf(ctx, "nxnative-switch2-probe: heap_bytes=%llu heap_test=%u heap_peak=%llu",
             (unsigned long long)ctx->heap_size, (unsigned)heap_ok,
             (unsigned long long)heap_peak);

    while (!hbx_stop_requested(ctx)) {
        uint64_t elapsed_ms;
        uint32_t gpu_handles = 0;
        hbx_input_poll(ctx, &input);
        if (input.pressed & (HBX_B | HBX_PLUS)) break;

        if (ctx->gpu.instance) gpu_handles++;
        if (ctx->gpu.physical) gpu_handles++;
        if (ctx->gpu.device) gpu_handles++;
        if (ctx->gpu.queue) gpu_handles++;
        if (ctx->gpu.swapchain) gpu_handles++;

        hbx_ui_begin(ctx, HBX_RGB(8, 18, 31));
        hbx_ui_rect(ctx, 88.0f, 88.0f, 1744.0f, 904.0f, 28.0f, HBX_RGB(16, 37, 57));
        hbx_ui_stroke(ctx, 88.0f, 88.0f, 1744.0f, 904.0f, 28.0f, 2.0f, HBX_RGB(45, 112, 145));
        hbx_ui_text(ctx, 140.0f, 132.0f, HBX_FONT_H1, "nxnative · Switch 2 bring-up", HBX_RGB(228, 244, 255));
        hbx_ui_text(ctx, 140.0f, 192.0f, HBX_FONT_SMALL, "HBLauncher userland test · ABI v3 · not NVN2", HBX_RGB(128, 180, 207));

        hbx_ui_text(ctx, 140.0f, 286.0f, HBX_FONT_H2, "Runtime and graphics handoff", HBX_RGB(110, 205, 235));
        used = 0; line[0] = 0;
        append_text(line, &used, "Vulkan display handles: "); append_u64(line, &used, gpu_handles); append_text(line, &used, "/5");
        hbx_ui_text(ctx, 140.0f, 340.0f, HBX_FONT_BODY, line, gpu_handles == 5 ? HBX_RGB(116, 230, 168) : HBX_RGB(255, 195, 105));

        used = 0; line[0] = 0;
        append_text(line, &used, "Swapchain: "); append_u64(line, &used, ctx->gpu.width);
        append_text(line, &used, " x "); append_u64(line, &used, ctx->gpu.height);
        append_text(line, &used, "  | images: "); append_u64(line, &used, ctx->gpu.image_count);
        hbx_ui_text(ctx, 140.0f, 390.0f, HBX_FONT_BODY, line, HBX_RGB(210, 228, 239));

        used = 0; line[0] = 0;
        append_text(line, &used, "Queue family: "); append_u64(line, &used, ctx->gpu.queue_family);
        append_text(line, &used, "  | UI renderer: "); append_text(line, &used, ui_ok ? "available" : "unavailable");
        hbx_ui_text(ctx, 140.0f, 440.0f, HBX_FONT_BODY, line, ui_ok ? HBX_RGB(116, 230, 168) : HBX_RGB(255, 195, 105));

        hbx_ui_text(ctx, 140.0f, 540.0f, HBX_FONT_H2, "CPU and memory smoke test", HBX_RGB(110, 205, 235));
        hbx_ui_text(ctx, 140.0f, 594.0f, HBX_FONT_BODY, heap_ok ? "64 KiB allocate / write / verify / free: PASS" : "64 KiB heap test: FAIL", heap_ok ? HBX_RGB(116, 230, 168) : HBX_RGB(255, 120, 120));

        used = 0; line[0] = 0;
        append_text(line, &used, "App heap: "); append_u64(line, &used, ctx->heap_size / 1024u);
        append_text(line, &used, " KiB  | peak allocation: "); append_u64(line, &used, heap_peak / 1024u);
        append_text(line, &used, " KiB");
        hbx_ui_text(ctx, 140.0f, 644.0f, HBX_FONT_SMALL, line, HBX_RGB(190, 213, 228));

        elapsed_ms = (hbx_now_ns(ctx) - started) / 1000000u;
        used = 0; line[0] = 0;
        append_text(line, &used, "Elapsed: "); append_u64(line, &used, elapsed_ms);
        append_text(line, &used, " ms  | frames: "); append_u64(line, &used, frame);
        hbx_ui_text(ctx, 140.0f, 716.0f, HBX_FONT_BODY, line, HBX_RGB(210, 228, 239));

        hbx_ui_text(ctx, 140.0f, 852.0f, HBX_FONT_SMALL, "Press B or + to return to HBLauncher.", HBX_RGB(128, 180, 207));
        if (hbx_ui_present(ctx) != HBX_OK) {
            hbx_log(ctx, "nxnative-switch2-probe: UI present failed");
            break;
        }
        frame++;
        hbx_frame_end(ctx);
        hbx_pace(ctx, &deadline, 60);
    }

    hbx_logf(ctx, "nxnative-switch2-probe: exit frames=%u heap_test=%u gpu_handles=%u",
             frame, (unsigned)heap_ok,
             (unsigned)((ctx->gpu.instance != 0) + (ctx->gpu.physical != 0) +
                       (ctx->gpu.device != 0) + (ctx->gpu.queue != 0) +
                       (ctx->gpu.swapchain != 0)));
    return heap_ok ? HBX_OK : HBX_ERR_HEAP;
}
