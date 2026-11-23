#include "CSkyLight.h"
#include <dlfcn.h>
#include <pthread.h>
#include <string.h>
#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>

typedef OSStatus (*focus_fn)(ProcessSerialNumber *, uint32_t, uint32_t);
typedef OSStatus (*pid_fn)(pid_t, ProcessSerialNumber *);
typedef AXError (*window_fn)(AXUIElementRef, uint32_t *);

static const char *names[] = {
    "_SLPSSetFrontProcessWithOptions",
    "GetProcessForPID",
    "_AXUIElementGetWindow"
};
static void *handles[2];
static void *symbols[3];
static const char *missing;
static pthread_once_t once = PTHREAD_ONCE_INIT;

static void *lookup_symbol(const char *name) {
    void *symbol = dlsym(handles[0], name);
    if (!symbol) symbol = dlsym(handles[1], name);
    return symbol;
}

static void resolve_real(void) {
    handles[0] = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY | RTLD_LOCAL
    );
    handles[1] = dlopen(
        "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
        RTLD_LAZY | RTLD_LOCAL
    );
    for (int i = 0; i < 3; i++) {
        symbols[i] = lookup_symbol(names[i]);
        if (!symbols[i] && !missing) missing = names[i];
    }
}

static hf_skylight_status resolve_fresh(const char *broken) {
    void *h[2] = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL),
        dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
            RTLD_LAZY | RTLD_LOCAL
        )
    };
    hf_skylight_status status = { true, NULL };
    for (int i = 0; i < 3; i++) {
        void *symbol = NULL;
        if (!broken || strcmp(broken, names[i]) != 0) {
            symbol = dlsym(h[0], names[i]);
            if (!symbol) symbol = dlsym(h[1], names[i]);
        }
        if (!symbol) {
            status.available = false;
            status.missing_symbol = names[i];
            break;
        }
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
    for (int i = 0; i < 3; i++) {
        if (strcmp(name, names[i]) == 0) return resolve_fresh(name);
    }
    return hf_skylight_resolve();
}

int hf_focus_without_raise(int32_t pid, uint32_t window_id) {
    hf_skylight_status status = hf_skylight_resolve();
    if (!status.available || pid <= 0) return -1;
    ProcessSerialNumber psn;
    if (((pid_fn)symbols[1])(pid, &psn) != noErr) return -1;
    /* 0x400 is kCPSNoWindows, selected by variant B in the probe table. */
    return (int)((focus_fn)symbols[0])(&psn, window_id, 0x400);
}

int hf_ax_window_id(const void *element, uint32_t *window_id) {
    hf_skylight_status status = hf_skylight_resolve();
    if (!element || !window_id || !status.available) return -1;
    return (int)((window_fn)symbols[2])((AXUIElementRef)element, window_id);
}
