// Bounded Horizon HIPC request parser. It only decodes the message envelope;
// it never dereferences guest-provided buffer addresses or handles.
#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NX_HIPC_HEADER_SIZE 8u
#define NX_HIPC_SPECIAL_HEADER_SIZE 4u
#define NX_HIPC_CMIF_REQUEST 4u
#define NX_HIPC_CMIF_CONTROL 5u
#define NX_HIPC_CMIF_REQUEST_WITH_CONTEXT 6u
#define NX_HIPC_CMIF_CONTROL_WITH_CONTEXT 7u

typedef enum {
    NX_HIPC_OK = 0,
    NX_HIPC_E_ARGUMENT = -1,
    NX_HIPC_E_BUFFER = -2,
    NX_HIPC_E_HEADER = -3
} nx_hipc_status;

typedef struct {
    uint32_t message_type;
    uint32_t num_send_statics;
    uint32_t num_send_buffers;
    uint32_t num_recv_buffers;
    uint32_t num_exch_buffers;
    uint32_t num_data_words;
    uint32_t num_recv_statics;
    uint32_t num_copy_handles;
    uint32_t num_move_handles;
    uint32_t send_pid;
    uint64_t pid;
    uint8_t recv_static_auto;
    const uint8_t *copy_handles;
    const uint8_t *move_handles;
    const uint8_t *send_statics;
    const uint8_t *send_buffers;
    const uint8_t *recv_buffers;
    const uint8_t *exch_buffers;
    const uint8_t *data_words;
    size_t data_size;
    const uint8_t *recv_list;
    const uint8_t *cmif_request;
    size_t cmif_available;
} nx_hipc_view;

// Parses one HIPC message from a bounded TLS IPC buffer. Descriptor contents
// are returned as byte ranges; guest addresses are never dereferenced.
nx_hipc_status nx_hipc_parse_request(
    const uint8_t *buffer, size_t buffer_size, nx_hipc_view *out);

#ifdef __cplusplus
}
#endif
