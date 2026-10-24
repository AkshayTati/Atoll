#include "include/MediaRemoteShim.h"

#include <dlfcn.h>
#include <dispatch/dispatch.h>

typedef void (*IsletMRGetInfoFn)(dispatch_queue_t queue, void (^block)(CFDictionaryRef info));
typedef unsigned char (*IsletMRSendCommandFn)(int command, CFDictionaryRef userInfo);

static void *gHandle = NULL;
static IsletMRGetInfoFn gGetInfo = NULL;
static IsletMRSendCommandFn gSendCommand = NULL;

static void islet_mr_load(void) {
    const char *candidates[] = {
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        "/System/Library/PrivateFrameworks/MediaRemote.framework/Versions/A/MediaRemote",
        NULL
    };

    for (int i = 0; candidates[i] != NULL && gHandle == NULL; i++) {
        gHandle = dlopen(candidates[i], RTLD_NOW | RTLD_LOCAL);
    }
    if (gHandle == NULL) {
        return;
    }

    gGetInfo = (IsletMRGetInfoFn)dlsym(gHandle, "MRMediaRemoteGetNowPlayingInfo");
    gSendCommand = (IsletMRSendCommandFn)dlsym(gHandle, "MRMediaRemoteSendCommand");
}

static void islet_mr_ensure_loaded(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        islet_mr_load();
    });
}

bool islet_mr_available(void) {
    islet_mr_ensure_loaded();
    return gGetInfo != NULL;
}

static void (*gCallback)(CFDictionaryRef, void *) = NULL;
static void *gContext = NULL;

void islet_mr_request_now_playing(void (*callback)(CFDictionaryRef, void *), void *context) {
    islet_mr_ensure_loaded();

    if (gGetInfo == NULL) {
        if (callback != NULL) {
            callback(NULL, context);
        }
        return;
    }

    gCallback = callback;
    gContext = context;

    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
    gGetInfo(queue, ^(CFDictionaryRef info) {
        void (*cb)(CFDictionaryRef, void *) = gCallback;
        void *ctx = gContext;
        gCallback = NULL;
        gContext = NULL;
        if (cb != NULL) {
            cb(info, ctx);
        }
    });
}

void islet_mr_send_command(int command) {
    islet_mr_ensure_loaded();
    if (gSendCommand != NULL) {
        (void)gSendCommand(command, NULL);
    }
}
