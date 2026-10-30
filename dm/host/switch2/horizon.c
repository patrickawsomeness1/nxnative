#include "horizon.h"
#include <string.h>

void nx_horizon_init(nx_horizon_context *ctx) {
    if (ctx) memset(ctx, 0, sizeof(*ctx));
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
