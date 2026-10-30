// Switch 2 Horizon compatibility boundary. This is a separate profile: it must not
// silently reuse Switch 1 SVC or service semantics without an evidence-backed adapter.
#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NX_HORIZON_MAX_SERVICES 32
#define NX_HORIZON_MAX_SESSIONS 64
#define NX_HORIZON_MAX_NAME 64
#define NX_CMIF_HEADER_SIZE 16u
#define NX_CMIF_VERSION_LEGACY 0u
#define NX_CMIF_VERSION_CONTEXT 1u
#define NX_CMIF_REQUEST_MAGIC 0x49434653u /* SFCI */
#define NX_CMIF_RESPONSE_MAGIC 0x4f434653u /* SFCO */

// These are host-internal status values, NOT Nintendo nn::Result values.
typedef enum {
    NX_HORIZON_OK = 0,
    NX_HORIZON_E_ARGUMENT = -1,
    NX_HORIZON_E_CAPACITY = -2,
    NX_HORIZON_E_DUPLICATE = -3,
    NX_HORIZON_E_NOT_FOUND = -4,
    NX_HORIZON_E_COMMAND = -5,
    NX_HORIZON_E_BUFFER = -6
} nx_horizon_status;

typedef nx_horizon_status (*nx_horizon_command_fn)(
    void *opaque, uint32_t command_id,
    const uint8_t *request, size_t request_size,
    uint8_t *response, size_t response_capacity, size_t *response_size);

typedef struct {
    char name[NX_HORIZON_MAX_NAME];
    void *opaque;
    nx_horizon_command_fn dispatch;
} nx_horizon_service;

typedef struct {
    uint32_t handle;
    uint16_t service_index;
    uint8_t active;
} nx_horizon_session;

typedef struct {
    nx_horizon_service services[NX_HORIZON_MAX_SERVICES];
    size_t service_count;
    nx_horizon_session sessions[NX_HORIZON_MAX_SESSIONS];
    uint32_t next_session_handle;
} nx_horizon_context;

void nx_horizon_init(nx_horizon_context *ctx);
nx_horizon_status nx_horizon_register_service(
    nx_horizon_context *ctx, const char *name, void *opaque,
    nx_horizon_command_fn dispatch);
nx_horizon_status nx_horizon_dispatch(
    nx_horizon_context *ctx, const char *service_name, uint32_t command_id,
    const uint8_t *request, size_t request_size,
    uint8_t *response, size_t response_capacity, size_t *response_size);
size_t nx_horizon_service_count(const nx_horizon_context *ctx);

// Host-internal session handles are not Horizon kernel handles. This layer
// models service-session ownership until verified HIPC handle transport exists.
nx_horizon_status nx_horizon_open_session(
    nx_horizon_context *ctx, const char *service_name, uint32_t *out_handle);
nx_horizon_status nx_horizon_close_session(
    nx_horizon_context *ctx, uint32_t handle);
nx_horizon_status nx_horizon_session_cmif_dispatch(
    nx_horizon_context *ctx, uint32_t handle,
    const uint8_t *request, size_t request_size,
    uint8_t *response, size_t response_capacity, size_t *response_size);
// HIPC transport for simple descriptor-free CMIF requests. Buffer/handle descriptors,
// domain objects, and SVC handle translation remain explicit unsupported cases.
nx_horizon_status nx_horizon_session_hipc_dispatch(
    nx_horizon_context *ctx, uint32_t handle,
    const uint8_t *hipc_request, size_t hipc_request_size,
    uint8_t *hipc_response, size_t hipc_response_capacity,
    size_t *hipc_response_size);
// CMIF framing only: the enclosing HIPC/TIPC transport and Nintendo result
// domain mapping are deliberately outside this API. A handler error is returned
// locally; no guessed Nintendo result code is serialized.
nx_horizon_status nx_horizon_cmif_dispatch(
    nx_horizon_context *ctx, const char *service_name,
    const uint8_t *cmif_request, size_t cmif_request_size,
    uint8_t *cmif_response, size_t cmif_response_capacity,
    size_t *cmif_response_size);


#ifdef __cplusplus
}
#endif
