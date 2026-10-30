#include "horizon.h"
#include <string.h>

void nx_horizon_init(nx_horizon_context *ctx) {
    if (ctx) { memset(ctx, 0, sizeof(*ctx)); ctx->next_session_handle = 1; }
}

nx_horizon_status nx_horizon_register_service(
    nx_horizon_context *ctx, const char *name, void *opaque,
    nx_horizon_command_fn dispatch) {
    if (!ctx || !name || !dispatch || !name[0]) return NX_HORIZON_E_ARGUMENT;
    size_t len = strlen(name);
    if (len >= NX_HORIZON_MAX_NAME) return NX_HORIZON_E_ARGUMENT;
    for (size_t i = 0; i < ctx->service_count; ++i)
        if (strcmp(ctx->services[i].name, name) == 0) return NX_HORIZON_E_DUPLICATE;
    if (ctx->service_count >= NX_HORIZON_MAX_SERVICES) return NX_HORIZON_E_CAPACITY;
    nx_horizon_service *service = &ctx->services[ctx->service_count++];
    memcpy(service->name, name, len + 1);
    service->opaque = opaque;
    service->dispatch = dispatch;
    return NX_HORIZON_OK;
}

nx_horizon_status nx_horizon_dispatch(
    nx_horizon_context *ctx, const char *service_name, uint32_t command_id,
    const uint8_t *request, size_t request_size,
    uint8_t *response, size_t response_capacity, size_t *response_size) {
    if (response_size) *response_size = 0;
    if (!ctx || !service_name || !response_size ||
        (request_size && !request) || (response_capacity && !response))
        return NX_HORIZON_E_ARGUMENT;
    for (size_t i = 0; i < ctx->service_count; ++i) {
        nx_horizon_service *service = &ctx->services[i];
        if (strcmp(service->name, service_name) != 0) continue;
        nx_horizon_status status = service->dispatch(
            service->opaque, command_id, request, request_size,
            response, response_capacity, response_size);
        if (*response_size > response_capacity) {
            *response_size = 0;
            return NX_HORIZON_E_BUFFER;
        }
        return status;
    }
    return NX_HORIZON_E_NOT_FOUND;
}

size_t nx_horizon_service_count(const nx_horizon_context *ctx) {
    return ctx ? ctx->service_count : 0;
}


static uint32_t nx_read_le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void nx_write_le32(uint8_t *p, uint32_t value) {
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
    p[2] = (uint8_t)(value >> 16);
    p[3] = (uint8_t)(value >> 24);
}

nx_horizon_status nx_horizon_cmif_dispatch(
    nx_horizon_context *ctx, const char *service_name,
    const uint8_t *cmif_request, size_t cmif_request_size,
    uint8_t *cmif_response, size_t cmif_response_capacity,
    size_t *cmif_response_size) {
    if (cmif_response_size) *cmif_response_size = 0;
    if (!ctx || !service_name || !cmif_request || !cmif_response ||
        !cmif_response_size) return NX_HORIZON_E_ARGUMENT;
    if (cmif_request_size < NX_CMIF_HEADER_SIZE) return NX_HORIZON_E_BUFFER;
    if (nx_read_le32(cmif_request) != NX_CMIF_REQUEST_MAGIC ||
        nx_read_le32(cmif_request + 4) != NX_CMIF_VERSION)
        return NX_HORIZON_E_COMMAND;
    if (cmif_response_capacity < NX_CMIF_HEADER_SIZE)
        return NX_HORIZON_E_BUFFER;

    const uint32_t command_id = nx_read_le32(cmif_request + 8);
    const uint32_t token = nx_read_le32(cmif_request + 12);
    size_t payload_size = 0;
    nx_horizon_status status = nx_horizon_dispatch(
        ctx, service_name, command_id,
        cmif_request + NX_CMIF_HEADER_SIZE,
        cmif_request_size - NX_CMIF_HEADER_SIZE,
        cmif_response + NX_CMIF_HEADER_SIZE,
        cmif_response_capacity - NX_CMIF_HEADER_SIZE, &payload_size);
    if (status != NX_HORIZON_OK) return status;

    nx_write_le32(cmif_response, NX_CMIF_RESPONSE_MAGIC);
    nx_write_le32(cmif_response + 4, NX_CMIF_VERSION);
    nx_write_le32(cmif_response + 8, 0); // success only; no guessed result mapping
    nx_write_le32(cmif_response + 12, token);
    *cmif_response_size = NX_CMIF_HEADER_SIZE + payload_size;
    return NX_HORIZON_OK;
}


nx_horizon_status nx_horizon_open_session(
    nx_horizon_context *ctx, const char *service_name, uint32_t *out_handle) {
    if (out_handle) *out_handle = 0;
    if (!ctx || !service_name || !out_handle) return NX_HORIZON_E_ARGUMENT;
    size_t service_index = ctx->service_count;
    for (size_t i = 0; i < ctx->service_count; ++i) {
        if (strcmp(ctx->services[i].name, service_name) == 0) {
            service_index = i;
            break;
        }
    }
    if (service_index == ctx->service_count) return NX_HORIZON_E_NOT_FOUND;
    for (size_t i = 0; i < NX_HORIZON_MAX_SESSIONS; ++i) {
        nx_horizon_session *session = &ctx->sessions[i];
        if (session->active) continue;
        uint32_t handle = 0;
        // Skip zero and any still-live handle if the counter wraps.
        for (size_t attempt = 0; attempt <= NX_HORIZON_MAX_SESSIONS; ++attempt) {
            uint32_t candidate = ctx->next_session_handle++;
            if (candidate == 0) continue;
            int in_use = 0;
            for (size_t j = 0; j < NX_HORIZON_MAX_SESSIONS; ++j) {
                if (ctx->sessions[j].active && ctx->sessions[j].handle == candidate) {
                    in_use = 1;
                    break;
                }
            }
            if (!in_use) { handle = candidate; break; }
        }
        if (handle == 0) return NX_HORIZON_E_CAPACITY;
        session->handle = handle;
        session->service_index = (uint16_t)service_index;
        session->active = 1;
        *out_handle = handle;
        return NX_HORIZON_OK;
    }
    return NX_HORIZON_E_CAPACITY;
}

nx_horizon_status nx_horizon_close_session(nx_horizon_context *ctx, uint32_t handle) {
    if (!ctx || handle == 0) return NX_HORIZON_E_ARGUMENT;
    for (size_t i = 0; i < NX_HORIZON_MAX_SESSIONS; ++i) {
        nx_horizon_session *session = &ctx->sessions[i];
        if (session->active && session->handle == handle) {
            memset(session, 0, sizeof(*session));
            return NX_HORIZON_OK;
        }
    }
    return NX_HORIZON_E_NOT_FOUND;
}

nx_horizon_status nx_horizon_session_cmif_dispatch(
    nx_horizon_context *ctx, uint32_t handle,
    const uint8_t *request, size_t request_size,
    uint8_t *response, size_t response_capacity, size_t *response_size) {
    if (response_size) *response_size = 0;
    if (!ctx || handle == 0 || !response_size) return NX_HORIZON_E_ARGUMENT;
    for (size_t i = 0; i < NX_HORIZON_MAX_SESSIONS; ++i) {
        nx_horizon_session *session = &ctx->sessions[i];
        if (session->active && session->handle == handle) {
            if (session->service_index >= ctx->service_count)
                return NX_HORIZON_E_NOT_FOUND;
            return nx_horizon_cmif_dispatch(ctx,
                ctx->services[session->service_index].name,
                request, request_size, response, response_capacity, response_size);
        }
    }
    return NX_HORIZON_E_NOT_FOUND;
}
