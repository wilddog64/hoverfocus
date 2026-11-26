#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    bool available;
    const char *missing_symbol;
} hf_skylight_status;

hf_skylight_status hf_skylight_resolve(void);
#define HF_RECORD_SIZE 0xf8
#define HF_CPS_USER_GENERATED 0x200
typedef struct { uint32_t high; uint32_t low; } hf_psn;
typedef struct {
    int32_t (*get_psn)(int32_t pid, hf_psn *psn);
    int32_t (*set_front)(hf_psn *psn, uint32_t window_id, uint32_t mode);
    int32_t (*post)(hf_psn *psn, uint8_t *record);
    void (*sleep_us)(uint32_t microseconds);
} hf_focus_ops;
void hf_record_make_key(uint8_t record[HF_RECORD_SIZE], uint32_t window_id, uint8_t phase);
void hf_record_activation(uint8_t record[HF_RECORD_SIZE], uint32_t window_id, bool activate);
int hf_focus_sequence(const hf_focus_ops *ops, int32_t pid, uint32_t window_id,
                      int32_t front_pid, uint32_t front_window_id);
int hf_focus_without_raise(int32_t pid, uint32_t window_id, int32_t front_pid, uint32_t front_window_id);
hf_skylight_status hf_skylight_resolve_with_symbol_override(const char *symbol_to_break);
int hf_ax_window_id(const void *ax_element, uint32_t *window_id);
