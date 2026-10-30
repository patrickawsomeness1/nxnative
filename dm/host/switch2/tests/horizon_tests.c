#include "../horizon.h"
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
    puts("Switch 2 Horizon service-router tests passed");
    return 0;
}
