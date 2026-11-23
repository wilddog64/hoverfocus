#include "CSkyLight.h"

hf_skylight_status hf_skylight_resolve(void) {
    hf_skylight_status s = { false, "not implemented" };
    return s;
}

int hf_focus_without_raise(int32_t pid, uint32_t window_id) {
    (void)pid;
    (void)window_id;
    return -1;
}

hf_skylight_status hf_skylight_resolve_with_symbol_override(const char *symbol_to_break) {
    (void)symbol_to_break;
    return hf_skylight_resolve();
}

int hf_ax_window_id(const void *ax_element, uint32_t *window_id) {
    (void)ax_element;
    (void)window_id;
    return -1;
}
