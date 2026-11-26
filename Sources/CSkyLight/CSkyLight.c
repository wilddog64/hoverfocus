#include "CSkyLight.h"
#include <dlfcn.h>
#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>

typedef OSStatus (*focus_fn)(ProcessSerialNumber *, uint32_t, uint32_t);
typedef OSStatus (*pid_fn)(pid_t, ProcessSerialNumber *);
typedef OSStatus (*post_fn)(ProcessSerialNumber *, void *);
typedef AXError (*window_fn)(AXUIElementRef, uint32_t *);

static const char *names[] = { "_SLPSSetFrontProcessWithOptions", "GetProcessForPID", "_AXUIElementGetWindow", "SLPSPostEventRecordTo" };
static void *handles[2];
static void *symbols[4];
static const char *missing;
static pthread_once_t once = PTHREAD_ONCE_INIT;

static void *lookup_symbol(const char *name) {
    void *symbol = dlsym(handles[0], name);
    if (!symbol) symbol = dlsym(handles[1], name);
    return symbol;
}

static void resolve_real(void) {
    handles[0] = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL);
    handles[1] = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY | RTLD_LOCAL);
    for (int i = 0; i < 4; i++) {
        symbols[i] = lookup_symbol(names[i]);
        if (!symbols[i] && !missing) missing = names[i];
    }
}

static hf_skylight_status resolve_fresh(const char *broken) {
    void *h[2] = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL),
        dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY | RTLD_LOCAL)
    };
    hf_skylight_status status = { true, NULL };
    for (int i = 0; i < 4; i++) {
        void *symbol = NULL;
        if (!broken || strcmp(broken, names[i]) != 0) {
            symbol = dlsym(h[0], names[i]);
            if (!symbol) symbol = dlsym(h[1], names[i]);
        }
        if (!symbol) { status.available = false; status.missing_symbol = names[i]; break; }
    }
    return status;
}

hf_skylight_status hf_skylight_resolve(void) {
    pthread_once(&once, resolve_real);
    hf_skylight_status status = { missing == NULL, missing };
    return status;
}

hf_skylight_status hf_skylight_resolve_with_symbol_override(const char *name) {
    if (!name) return hf_skylight_resolve();
    for (int i = 0; i < 4; i++) if (strcmp(name, names[i]) == 0) return resolve_fresh(name);
    return hf_skylight_resolve();
}

void hf_record_make_key(uint8_t record[HF_RECORD_SIZE], uint32_t window_id, uint8_t phase) {
    if (!record) return;
    memset(record, 0, HF_RECORD_SIZE);
    record[0x04] = 0xf8; record[0x08] = phase; record[0x3a] = 0x10;
    memset(record + 0x20, 0xff, 0x10);
    for (int i = 0; i < 4; i++) record[0x3c + i] = (uint8_t)(window_id >> (8 * i));
}

void hf_record_activation(uint8_t record[HF_RECORD_SIZE], uint32_t window_id, bool activate) {
    if (!record) return;
    memset(record, 0, HF_RECORD_SIZE);
    record[0x04] = 0xf8; record[0x08] = 0x0d; record[0x8a] = activate ? 0x01 : 0x02;
    for (int i = 0; i < 4; i++) record[0x3c + i] = (uint8_t)(window_id >> (8 * i));
}

int hf_focus_sequence(const hf_focus_ops *ops, int32_t pid, uint32_t window_id, int32_t front_pid, uint32_t front_window_id) {
    if (pid <= 0 || !ops || !ops->get_psn || !ops->set_front || !ops->post || !ops->sleep_us) return -1;
    hf_psn psn;
    if (ops->get_psn(pid, &psn) != 0) return -1;
    int first = 0;
    if (front_pid == pid && front_window_id != 0 && front_window_id != window_id) {
        uint8_t record[HF_RECORD_SIZE];
        hf_record_activation(record, front_window_id, false);
        int rc = ops->post(&psn, record); if (rc && !first) first = rc;
        ops->sleep_us(40000);
        hf_record_activation(record, window_id, true);
        rc = ops->post(&psn, record); if (rc && !first) first = rc;
    }
    int rc = ops->set_front(&psn, window_id, HF_CPS_USER_GENERATED); if (rc && !first) first = rc;
    uint8_t record[HF_RECORD_SIZE];
    hf_record_make_key(record, window_id, 1); rc = ops->post(&psn, record); if (rc && !first) first = rc;
    hf_record_make_key(record, window_id, 2); rc = ops->post(&psn, record); if (rc && !first) first = rc;
    return first;
}

static int32_t real_get_psn(int32_t pid, hf_psn *psn) {
    ProcessSerialNumber native;
    int32_t rc = (int32_t)((pid_fn)symbols[1])((pid_t)pid, &native);
    psn->high = native.highLongOfPSN; psn->low = native.lowLongOfPSN;
    return rc;
}
static ProcessSerialNumber native_psn(hf_psn *psn) { ProcessSerialNumber native = { psn->high, psn->low }; return native; }
static int32_t real_set_front(hf_psn *psn, uint32_t wid, uint32_t mode) { ProcessSerialNumber native = native_psn(psn); return (int32_t)((focus_fn)symbols[0])(&native, wid, mode); }
static int32_t real_post(hf_psn *psn, uint8_t *record) { ProcessSerialNumber native = native_psn(psn); return (int32_t)((post_fn)symbols[3])(&native, record); }
static void real_sleep(uint32_t microseconds) { usleep((useconds_t)microseconds); }

int hf_focus_without_raise(int32_t pid, uint32_t window_id, int32_t front_pid, uint32_t front_window_id) {
    hf_skylight_status status = hf_skylight_resolve();
    if (!status.available) return -1;
    const hf_focus_ops ops = { real_get_psn, real_set_front, real_post, real_sleep };
    return hf_focus_sequence(&ops, pid, window_id, front_pid, front_window_id);
}

int hf_ax_window_id(const void *element, uint32_t *window_id) {
    hf_skylight_status status = hf_skylight_resolve();
    if (!element || !window_id || !status.available) return -1;
    return (int)((window_fn)symbols[2])((AXUIElementRef)element, window_id);
}
