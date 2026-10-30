#include "../horizon.h"
#include "../hipc.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static nx_horizon_status echo_command(void *opaque, uint32_t command_id,
    const uint8_t *request, size_t request_size, uint8_t *response,
    size_t response_capacity, size_t *response_size) {
    (void)opaque;
    if (command_id != 7) return NX_HORIZON_E_COMMAND;
    if (request_size > response_capacity) return NX_HORIZON_E_BUFFER;
    if (request_size) memcpy(response, request, request_size);
    *response_size = request_size;
    return NX_HORIZON_OK;
}

int main(void) {
    nx_horizon_context ctx;
    nx_horizon_init(&ctx);
    assert(nx_horizon_service_count(&ctx) == 0);
    assert(nx_horizon_register_service(&ctx, "sm:", NULL, echo_command) == NX_HORIZON_OK);
    assert(nx_horizon_register_service(&ctx, "sm:", NULL, echo_command) == NX_HORIZON_E_DUPLICATE);
    assert(nx_horizon_service_count(&ctx) == 1);

    const uint8_t input[] = {1, 2, 3, 4};
    uint8_t output[4] = {0};
    size_t output_size = 0;
    assert(nx_horizon_dispatch(&ctx, "sm:", 7, input, sizeof(input),
        output, sizeof(output), &output_size) == NX_HORIZON_OK);
    assert(output_size == sizeof(input));
    assert(memcmp(input, output, sizeof(input)) == 0);
    assert(nx_horizon_dispatch(&ctx, "sm:", 99, input, sizeof(input),
        output, sizeof(output), &output_size) == NX_HORIZON_E_COMMAND);
    assert(nx_horizon_dispatch(&ctx, "not-a-service", 7, input, sizeof(input),
        output, sizeof(output), &output_size) == NX_HORIZON_E_NOT_FOUND);
    assert(nx_horizon_dispatch(&ctx, "sm:", 7, input, sizeof(input),
        output, 2, &output_size) == NX_HORIZON_E_BUFFER);

    // CMIF request: SFCI, version 1, command 7, token 0x12345678, payload.
    const uint8_t cmif_request[] = {
        0x53,0x46,0x43,0x49, 1,0,0,0, 7,0,0,0,
        0x78,0x56,0x34,0x12, 9,8,7
    };
    uint8_t cmif_response[64] = {0};
    size_t cmif_response_size = 0;
    assert(nx_horizon_cmif_dispatch(&ctx, "sm:", cmif_request,
        sizeof(cmif_request), cmif_response, sizeof(cmif_response),
        &cmif_response_size) == NX_HORIZON_OK);
    assert(cmif_response_size == NX_CMIF_HEADER_SIZE + 3);
    assert(cmif_response[0] == 0x53 && cmif_response[1] == 0x46 &&
        cmif_response[2] == 0x43 && cmif_response[3] == 0x4f);
    assert(cmif_response[12] == 0x78 && cmif_response[13] == 0x56 &&
        cmif_response[14] == 0x34 && cmif_response[15] == 0x12);
    assert(cmif_response[16] == 9 && cmif_response[17] == 8 &&
        cmif_response[18] == 7);

    // Legacy CMIF v0 requests are also valid and the SFCO response echoes v0.
    const uint8_t cmif_v0_request[] = {
        0x53,0x46,0x43,0x49, 0,0,0,0, 7,0,0,0,
        0x34,0x12,0,0, 4,5,6
    };
    assert(nx_horizon_cmif_dispatch(&ctx, "sm:", cmif_v0_request,
        sizeof(cmif_v0_request), cmif_response, sizeof(cmif_response),
        &cmif_response_size) == NX_HORIZON_OK);
    assert(cmif_response[4] == 0 && cmif_response[5] == 0 &&
        cmif_response[6] == 0 && cmif_response[7] == 0);
    const uint8_t bad_magic[] = {0};
    assert(nx_horizon_cmif_dispatch(&ctx, "sm:", bad_magic,
        sizeof(bad_magic), cmif_response, sizeof(cmif_response),
        &cmif_response_size) == NX_HORIZON_E_BUFFER);

    uint32_t session = 0;
    assert(nx_horizon_open_session(&ctx, "sm:", &session) == NX_HORIZON_OK);
    assert(session != 0);
    assert(nx_horizon_session_cmif_dispatch(&ctx, session, cmif_request,
        sizeof(cmif_request), cmif_response, sizeof(cmif_response),
        &cmif_response_size) == NX_HORIZON_OK);
    assert(nx_horizon_close_session(&ctx, session) == NX_HORIZON_OK);
    assert(nx_horizon_session_cmif_dispatch(&ctx, session, cmif_request,
        sizeof(cmif_request), cmif_response, sizeof(cmif_response),
        &cmif_response_size) == NX_HORIZON_E_NOT_FOUND);
    assert(nx_horizon_close_session(&ctx, session) == NX_HORIZON_E_NOT_FOUND);

    // Handle allocation must skip zero and avoid collisions across uint32 wrap.
    ctx.next_session_handle = UINT32_MAX;
    uint32_t last_handle = 0, wrapped_handle = 0;
    assert(nx_horizon_open_session(&ctx, "sm:", &last_handle) == NX_HORIZON_OK);
    assert(last_handle == UINT32_MAX);
    assert(nx_horizon_open_session(&ctx, "sm:", &wrapped_handle) == NX_HORIZON_OK);
    assert(wrapped_handle == 1 && wrapped_handle != last_handle);
    assert(nx_horizon_close_session(&ctx, last_handle) == NX_HORIZON_OK);
    assert(nx_horizon_close_session(&ctx, wrapped_handle) == NX_HORIZON_OK);
    // Minimal HIPC Request (type 4), with CMIF v0 aligned to 16 bytes.
    uint8_t hipc[128] = {0};
    uint32_t hipc_word0 = NX_HIPC_CMIF_REQUEST;
    uint32_t hipc_word1 = 7; // 7 data words: 8-byte pad + 16-byte CMIF header + 3-byte payload.
    memcpy(hipc, &hipc_word0, sizeof(hipc_word0));
    memcpy(hipc + 4, &hipc_word1, sizeof(hipc_word1));
    const uint32_t sfci = 0x49434653u;
    memcpy(hipc + 16, &sfci, sizeof(sfci));
    uint32_t version0 = 0, command7 = 7, token = 0x12345678;
    memcpy(hipc + 20, &version0, 4);
    memcpy(hipc + 24, &command7, 4);
    memcpy(hipc + 28, &token, 4);
    hipc[32] = 9; hipc[33] = 8; hipc[34] = 7;
    nx_hipc_view hipc_view;
    assert(nx_hipc_parse_request(hipc, 36, &hipc_view) == NX_HIPC_OK);
    assert(hipc_view.message_type == NX_HIPC_CMIF_REQUEST);
    assert(hipc_view.num_data_words == 7 && hipc_view.data_size == 28);
    assert(hipc_view.cmif_request == hipc + 16 && hipc_view.cmif_available == 20);
    assert(hipc_view.num_send_buffers == 0 && hipc_view.num_copy_handles == 0);

    uint32_t hipc_session = 0;
    assert(nx_horizon_open_session(&ctx, "sm:", &hipc_session) == NX_HORIZON_OK);
    uint8_t hipc_response[128] = {0};
    size_t hipc_response_size = 0;
    assert(nx_horizon_session_hipc_dispatch(&ctx, hipc_session, hipc, 36,
        hipc_response, sizeof(hipc_response), &hipc_response_size) == NX_HORIZON_OK);
    assert(hipc_response_size == 36);
    uint32_t response_word0 = 1, response_word1 = 0;
    memcpy(&response_word0, hipc_response, 4);
    memcpy(&response_word1, hipc_response + 4, 4);
    assert(response_word0 == 0 && response_word1 == 7);
    const uint32_t sfco = 0x4f434653u;
    uint32_t response_magic = 0, response_version = 1, response_result = 1;
    memcpy(&response_magic, hipc_response + 16, 4);
    memcpy(&response_version, hipc_response + 20, 4);
    memcpy(&response_result, hipc_response + 24, 4);
    assert(response_magic == sfco && response_version == 0 && response_result == 0);
    assert(hipc_response[32] == 9 && hipc_response[33] == 8 &&
        hipc_response[34] == 7);
    assert(nx_horizon_close_session(&ctx, hipc_session) == NX_HORIZON_OK);

    // Context-aware CMIF v1 uses HIPC RequestWithContext (type 6).
    hipc_word0 = NX_HIPC_CMIF_REQUEST_WITH_CONTEXT;
    memcpy(hipc, &hipc_word0, 4);
    uint32_t version1 = 1;
    memcpy(hipc + 20, &version1, 4);
    assert(nx_hipc_parse_request(hipc, 36, &hipc_view) == NX_HIPC_OK);
    assert(hipc_view.cmif_request == hipc + 16);

    // Special header, PID, handles, all four descriptor groups, and one recv-static entry.
    memset(hipc, 0, sizeof(hipc));
    hipc_word0 = NX_HIPC_CMIF_REQUEST | (1u << 16) | (1u << 20) |
        (1u << 24) | (1u << 28);
    hipc_word1 = 7u | (3u << 10) | (1u << 31);
    memcpy(hipc, &hipc_word0, 4);
    memcpy(hipc + 4, &hipc_word1, 4);
    uint32_t special = 1u | (1u << 1) | (1u << 5); // PID + one copy + one move handle.
    memcpy(hipc + 8, &special, 4);
    const uint64_t pid = 0x1122334455667788ULL;
    memcpy(hipc + 12, &pid, 8);
    memcpy(hipc + 80, &sfci, 4);
    memcpy(hipc + 84, &version0, 4);
    memcpy(hipc + 88, &command7, 4);
    memcpy(hipc + 92, &token, 4);
    hipc[96] = 1; hipc[97] = 2; hipc[98] = 3;
    assert(nx_hipc_parse_request(hipc, 108, &hipc_view) == NX_HIPC_OK);
    assert(hipc_view.send_pid && hipc_view.pid == pid);
    assert(hipc_view.num_copy_handles == 1 && hipc_view.num_move_handles == 1);
    assert(hipc_view.num_send_statics == 1 && hipc_view.num_send_buffers == 1);
    assert(hipc_view.num_recv_buffers == 1 && hipc_view.num_exch_buffers == 1);
    assert(hipc_view.num_recv_statics == 1 && !hipc_view.recv_static_auto);
    assert(hipc_view.copy_handles == hipc + 20 && hipc_view.move_handles == hipc + 24);
    assert(hipc_view.send_statics == hipc + 28 && hipc_view.send_buffers == hipc + 36);
    assert(hipc_view.recv_buffers == hipc + 48 && hipc_view.exch_buffers == hipc + 60);
    assert(hipc_view.data_words == hipc + 72 && hipc_view.recv_list == hipc + 100);
    assert(hipc_view.cmif_request == hipc + 80);

    // Malformed and truncated messages fail before exposing any guest pointers.
    assert(nx_hipc_parse_request(hipc, 7, &hipc_view) == NX_HIPC_E_BUFFER);
    memset(hipc, 0, sizeof(hipc));
    hipc_word0 = NX_HIPC_CMIF_REQUEST;
    hipc_word1 = 1u << 10; // Reserved receive-static mode.
    memcpy(hipc, &hipc_word0, 4); memcpy(hipc + 4, &hipc_word1, 4);
    assert(nx_hipc_parse_request(hipc, sizeof(hipc), &hipc_view) == NX_HIPC_E_HEADER);
    hipc_word1 = 0x3ffu;
    memcpy(hipc + 4, &hipc_word1, 4);
    assert(nx_hipc_parse_request(hipc, sizeof(hipc), &hipc_view) == NX_HIPC_E_BUFFER);
    hipc_word1 = 7u;
    memcpy(hipc + 4, &hipc_word1, 4);
    memcpy(hipc + 16, &sfci, 4);
    memcpy(hipc + 20, &version1, 4); // type 4 requires CMIF v0.
    assert(nx_hipc_parse_request(hipc, 36, &hipc_view) == NX_HIPC_E_HEADER);

    puts("Switch 2 Horizon service, CMIF, HIPC, and session tests passed");
    return 0;
}
