#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import <stdio.h>
#import <stdlib.h>

typedef void (*GetClientsFn)(dispatch_queue_t, void (^)(NSArray *));
typedef int32_t (*ClientPIDFn)(id);
typedef CFStringRef (*ClientStrFn)(id);
typedef void (*InfoForClientFn)(id, id, int32_t, dispatch_queue_t, void (^)(NSDictionary *));
typedef bool (*SendToClientFn)(int32_t, CFDictionaryRef, id, id, CFDictionaryRef, dispatch_queue_t, void (^)(id));
typedef id (*GetLocalOriginFn)(void);

static GetClientsFn getClients;
static ClientPIDFn getClientPID;
static ClientStrFn getClientBundle;
static InfoForClientFn getInfoForClient;
static SendToClientFn sendToClient;
static GetLocalOriginFn getLocalOrigin;

static void *mrSym(CFBundleRef bundle, const char *name) {
    CFStringRef string = CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8);
    void *pointer = CFBundleGetFunctionPointerForName(bundle, string);
    CFRelease(string);
    return pointer;
}

static void loadSymbols(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [NSURL fileURLWithPath:@"/System/Library/PrivateFrameworks/MediaRemote.framework"];
        CFBundleRef bundle = CFBundleCreate(kCFAllocatorDefault, (__bridge CFURLRef)url);
        if (!bundle) {
            return;
        }
        getClients = (GetClientsFn)mrSym(bundle, "MRMediaRemoteGetNowPlayingClients");
        getClientPID = (ClientPIDFn)mrSym(bundle, "MRNowPlayingClientGetProcessIdentifier");
        getClientBundle = (ClientStrFn)mrSym(bundle, "MRNowPlayingClientGetBundleIdentifier");
        getInfoForClient = (InfoForClientFn)mrSym(bundle, "MRMediaRemoteGetNowPlayingInfoForClient");
        sendToClient = (SendToClientFn)mrSym(bundle, "MRMediaRemoteSendCommandToClient");
        getLocalOrigin = (GetLocalOriginFn)mrSym(bundle, "MRMediaRemoteGetLocalOrigin");
    });
}

static NSString *envString(const char *name) {
    const char *value = getenv(name);
    return value ? [NSString stringWithUTF8String:value] : nil;
}

static NSArray *fetchClients(void) {
    loadSymbols();
    if (!getClients) {
        return @[];
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSArray *clients = @[];
    void (^completion)(NSArray *) = ^(NSArray *result) {
        clients = result ?: @[];
        dispatch_semaphore_signal(semaphore);
    };
    getClients(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), [completion copy]);

    if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC)) != 0) {
        return @[];
    }
    return clients;
}

static NSString *clientBundleID(id client) {
    if (!getClientBundle) {
        return @"";
    }
    CFStringRef value = getClientBundle(client);
    return value ? (__bridge NSString *)value : @"";
}

static NSDictionary *clientInfo(id client) {
    if (!getInfoForClient) {
        return @{};
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSDictionary *information = nil;
    void (^completion)(NSDictionary *) = ^(NSDictionary *info) {
        information = info;
        dispatch_semaphore_signal(semaphore);
    };
    getInfoForClient(client, nil, 0, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), [completion copy]);

    if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC)) != 0) {
        return @{};
    }
    return information ?: @{};
}

static NSArray *clientPayload(void) {
    NSArray *clients = fetchClients();
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:clients.count];

    for (id client in clients) {
        NSString *bundleID = clientBundleID(client);
        if (bundleID.length == 0) {
            continue;
        }

        NSDictionary *info = clientInfo(client);
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        entry[@"bundle"] = bundleID;
        entry[@"pid"] = @(getClientPID ? getClientPID(client) : 0);

        id title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
        id artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
        id album = info[@"kMRMediaRemoteNowPlayingInfoAlbum"];
        id duration = info[@"kMRMediaRemoteNowPlayingInfoDuration"];
        id elapsed = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
        id rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
        id artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];

        if ([title isKindOfClass:[NSString class]]) entry[@"title"] = title;
        if ([artist isKindOfClass:[NSString class]]) entry[@"artist"] = artist;
        if ([album isKindOfClass:[NSString class]]) entry[@"album"] = album;
        if ([duration isKindOfClass:[NSNumber class]]) entry[@"duration"] = duration;
        if ([elapsed isKindOfClass:[NSNumber class]]) entry[@"elapsed"] = elapsed;
        if ([rate isKindOfClass:[NSNumber class]]) entry[@"rate"] = rate;
        if ([artwork isKindOfClass:[NSData class]]) {
            entry[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
        }

        [result addObject:entry];
    }

    [result sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"bundle"] compare:b[@"bundle"]];
    }];
    return result;
}

static bool sendCommand(NSString *bundleID, int32_t command) {
    loadSymbols();
    if (!sendToClient || !getLocalOrigin) {
        return false;
    }

    NSArray *clients = fetchClients();
    id target = nil;
    for (id client in clients) {
        if ([clientBundleID(client) isEqualToString:bundleID]) {
            target = client;
            break;
        }
    }
    if (!target) {
        return false;
    }

    id origin = getLocalOrigin();
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    void (^completion)(id) = ^(id result) {
        dispatch_semaphore_signal(semaphore);
    };
    bool sent = sendToClient(command, NULL, origin, target, NULL, NULL, [completion copy]);

    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    return sent;
}

void islet_run(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);

        NSString *command = envString("ISLET_HELPER_COMMAND") ?: @"list";
        if ([command isEqualToString:@"send"]) {
            NSString *bundleID = envString("ISLET_HELPER_BUNDLE") ?: @"";
            int32_t code = (int32_t)[envString("ISLET_HELPER_CODE") intValue];
            bool ok = sendCommand(bundleID, code);
            printf("%s\n", ok ? "ok" : "failed");
            return;
        }

        NSArray *payload = clientPayload();
        NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
        if (json) {
            fwrite(json.bytes, 1, json.length, stdout);
            fputc('\n', stdout);
        } else {
            printf("[]\n");
        }
        fflush(stdout);
    }
}
