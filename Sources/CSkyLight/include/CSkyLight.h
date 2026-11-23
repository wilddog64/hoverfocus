#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    bool available;
    const char *missing_symbol;
} hf_skylight_status;

hf_skylight_status hf_skylight_resolve(void);
int hf_focus_without_raise(int32_t pid, uint32_t window_id);
hf_skylight_status hf_skylight_resolve_with_symbol_override(const char *symbol_to_break);
int hf_ax_window_id(const void *ax_element, uint32_t *window_id);
