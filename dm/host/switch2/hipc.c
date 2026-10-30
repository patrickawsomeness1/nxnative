#include "hipc.h"
#include <string.h>

static uint32_t nx_hipc_read_le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t nx_hipc_read_le64(const uint8_t *p) {
    return (uint64_t)nx_hipc_read_le32(p) |
        ((uint64_t)nx_hipc_read_le32(p + 4) << 32);
}

static int nx_hipc_take(
    const uint8_t *buffer, size_t buffer_size, size_t *offset,
    size_t count, size_t item_size, const uint8_t **out) {
    if (count && item_size > SIZE_MAX / count) return 0;
    size_t bytes = count * item_size;
    if (*offset > buffer_size || bytes > buffer_size - *offset) return 0;
    if (out) *out = buffer + *offset;
    *offset += bytes;
    return 1;
}

nx_hipc_status nx_hipc_parse_request(
    const uint8_t *buffer, size_t buffer_size, nx_hipc_view *out) {
    if (out) memset(out, 0, sizeof(*out));
    if (!buffer || !out) return NX_HIPC_E_ARGUMENT;
    if (buffer_size < NX_HIPC_HEADER_SIZE) return NX_HIPC_E_BUFFER;

    const uint32_t word0 = nx_hipc_read_le32(buffer);
    const uint32_t word1 = nx_hipc_read_le32(buffer + 4);
    out->message_type = word0 & 0xffffu;
    out->num_send_statics = (word0 >> 16) & 0xfu;
    out->num_send_buffers = (word0 >> 20) & 0xfu;
    out->num_recv_buffers = (word0 >> 24) & 0xfu;
    out->num_exch_buffers = (word0 >> 28) & 0xfu;
    out->num_data_words = word1 & 0x3ffu;
    const uint32_t recv_mode = (word1 >> 10) & 0xfu;
    const int has_special_header = (word1 >> 31) & 1u;
    if (recv_mode == 1u) return NX_HIPC_E_HEADER;
    if (recv_mode == 2u) {
        out->recv_static_auto = 1;
        out->num_recv_statics = UINT32_MAX;
    } else if (recv_mode > 2u) {
        out->num_recv_statics = recv_mode - 2u;
    }

    size_t offset = NX_HIPC_HEADER_SIZE;
    if (has_special_header) {
        const uint8_t *special = NULL;
        if (!nx_hipc_take(buffer, buffer_size, &offset, 1,
                NX_HIPC_SPECIAL_HEADER_SIZE, &special))
            return NX_HIPC_E_BUFFER;
        const uint32_t special_word = nx_hipc_read_le32(special);
        out->send_pid = special_word & 1u;
        out->num_copy_handles = (special_word >> 1) & 0xfu;
        out->num_move_handles = (special_word >> 5) & 0xfu;
        if (out->send_pid) {
            const uint8_t *pid = NULL;
            if (!nx_hipc_take(buffer, buffer_size, &offset, 1, 8, &pid))
                return NX_HIPC_E_BUFFER;
            out->pid = nx_hipc_read_le64(pid);
        }
    }

    if (!nx_hipc_take(buffer, buffer_size, &offset, out->num_copy_handles, 4, &out->copy_handles) ||
        !nx_hipc_take(buffer, buffer_size, &offset, out->num_move_handles, 4, &out->move_handles) ||
        !nx_hipc_take(buffer, buffer_size, &offset, out->num_send_statics, 8, &out->send_statics) ||
        !nx_hipc_take(buffer, buffer_size, &offset, out->num_send_buffers, 12, &out->send_buffers) ||
        !nx_hipc_take(buffer, buffer_size, &offset, out->num_recv_buffers, 12, &out->recv_buffers) ||
        !nx_hipc_take(buffer, buffer_size, &offset, out->num_exch_buffers, 12, &out->exch_buffers) ||
        !nx_hipc_take(buffer, buffer_size, &offset, out->num_data_words, 4, &out->data_words))
        return NX_HIPC_E_BUFFER;

    out->data_size = (size_t)out->num_data_words * 4u;
    if (out->recv_static_auto) {
        // Auto receive-static mode has no fixed-size descriptor list in the request.
        out->recv_list = buffer + offset;
    } else if (!nx_hipc_take(buffer, buffer_size, &offset,
            out->num_recv_statics, 8, &out->recv_list)) {
        return NX_HIPC_E_BUFFER;
    }

    if (out->message_type >= NX_HIPC_CMIF_REQUEST &&
        out->message_type <= NX_HIPC_CMIF_CONTROL_WITH_CONTEXT) {
        if (!out->data_words || out->data_size > buffer_size)
            return NX_HIPC_E_BUFFER;
        const size_t data_offset = (size_t)(out->data_words - buffer);
        if (data_offset > SIZE_MAX - 15u) return NX_HIPC_E_BUFFER;
        const size_t cmif_offset = (data_offset + 15u) & ~(size_t)15u;
        const size_t data_end = data_offset + out->data_size;
        if (cmif_offset > data_end || data_end - cmif_offset < 16u)
            return NX_HIPC_E_BUFFER;
        const uint8_t *cmif = buffer + cmif_offset;
        const uint32_t magic = nx_hipc_read_le32(cmif);
        const uint32_t version = nx_hipc_read_le32(cmif + 4);
        const uint32_t expected_version =
            (out->message_type == NX_HIPC_CMIF_REQUEST_WITH_CONTEXT ||
             out->message_type == NX_HIPC_CMIF_CONTROL_WITH_CONTEXT) ? 1u : 0u;
        if (magic != 0x49434653u || version != expected_version)
            return NX_HIPC_E_HEADER;
        out->cmif_request = cmif;
        out->cmif_available = data_end - cmif_offset;
    }
    return NX_HIPC_OK;
}
