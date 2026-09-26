#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <errno.h>
#import <unistd.h>
#import <notify.h>
#import <string.h>
#import <atomic>
#import <os/log.h>
#import "Shared.h"

static std::atomic<int> mask{NSUnknown};
static std::atomic<bool> busy{false};
static std::atomic<uint64_t> generation{0};
static NSString *identity, *displayName;
static dispatch_queue_t worker;
static int changeToken;
static std::atomic<double> nextRefresh{0};
static std::atomic<double> lastReply{0};
static thread_local bool inside = false;
static dispatch_source_t registrationTimer;
static std::atomic<bool> hooksReady{false};
static std::atomic<unsigned> additionalHooks{0};
static std::atomic<bool> sawSocket{false};
static os_log_t clientLog;
static bool attemptedReply = false;
static bool brokerReachable = false; // worker queue only

static void NSApplyReply(NSDictionary *reply, uint64_t version) {
    NSNumber *value = reply[@"mask"], *active = reply[@"enabled"];
    BOOL valid = [value isKindOfClass:NSNumber.class] && [active isKindOfClass:NSNumber.class] &&
        (value.intValue == NSUnknown || NSSelectableRule(value.intValue));
    if (!attemptedReply || valid != brokerReachable) {
        attemptedReply = true;
        os_log_with_type(clientLog, OS_LOG_TYPE_DEFAULT, "broker reply %{public}s", valid ? "received" : "missing or invalid; covered traffic blocked");
        brokerReachable = valid;
    }
    if (generation.load() != version) return;
    mask.store(valid && !active.boolValue ? NSBoth : (valid ? value.intValue : NSUnknown));
    lastReply.store(valid ? NSProcessInfo.processInfo.systemUptime : 0);
}

void NSClientHooksReady(unsigned extraHooks) {
    additionalHooks.store(extraHooks);
    hooksReady.store(true);
    os_log_with_type(clientLog, OS_LOG_TYPE_DEFAULT, "hook setup completed; additional entries: %u", extraHooks);
    registrationTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, worker);
    dispatch_source_set_timer(registrationTimer, DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(registrationTimer, ^{
        @autoreleasepool {
            inside = true;
            @try {
                NSDictionary *info = @{@"identity": identity, @"name": displayName, @"kind": @"register",
                    @"host": @"", @"port": @0, @"direction": @(NSOutbound), @"pid": @(getpid()),
                    @"hooks": @(hooksReady.load()), @"extraHooks": @(additionalHooks.load())};
                uint64_t version = generation.load();
                NSApplyReply(NSRequestPolicy(info), version);
            } @catch (NSException *exception) {
                mask.store(NSUnknown);
                lastReply.store(0);
            } @finally { inside = false; }
        }
    });
    dispatch_resume(registrationTimer);
}

void NSStartClient(void) {
    NSBundle *bundle = NSBundle.mainBundle;
    identity = bundle.bundleIdentifier ?: [@"exec:" stringByAppendingString:NSProcessInfo.processInfo.arguments.firstObject ?: @"unknown"];
    displayName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"] ?: NSProcessInfo.processInfo.processName;
    if (displayName.length > 128) displayName = [displayName substringToIndex:128];
    clientLog = os_log_create("com.netshield", "client");
    os_log_with_type(clientLog, OS_LOG_TYPE_DEFAULT, "client loaded: %{public}@ pid %d", identity, getpid());
    worker = dispatch_queue_create("com.netshield.client", DISPATCH_QUEUE_SERIAL);
    notify_register_dispatch(NSChanged, &changeToken, worker, ^(int token) {
        generation.fetch_add(1);
        mask.store(NSUnknown);
        nextRefresh.store(0);
    });
}

bool NSCheckSocket(int fd, int direction, const struct sockaddr *address, socklen_t length) {
    int savedErrno = errno;
    if (inside || !worker) return true;
    struct sockaddr_storage local = {};
    socklen_t size = sizeof(local);
    // Only known non-sockets/invalid descriptors pass through on classification failure.
    // A sandbox or transient getsockname failure must not grant network access.
    inside = true;
    int classified = getsockname(fd, (struct sockaddr *)&local, &size);
    int classificationError = errno;
    if (classified != 0 || (local.ss_family != AF_INET && local.ss_family != AF_INET6)) {
        bool allowed = classified == 0 || classificationError == ENOTSOCK || classificationError == EBADF;
        inside = false;
        errno = allowed ? savedErrno : EACCES;
        return allowed;
    }
    if (!sawSocket.exchange(true)) os_log_with_type(clientLog, OS_LOG_TYPE_DEFAULT, "first IP socket intercepted");
    @autoreleasepool {
        double now = NSProcessInfo.processInfo.systemUptime;
        bool expected = false;
        if (now >= nextRefresh.load() && busy.compare_exchange_strong(expected, true)) {
            struct sockaddr_storage peer = {};
            socklen_t peerSize = sizeof(peer);
            if (address && length >= sizeof(struct sockaddr) && length <= sizeof(peer)) {
                memcpy(&peer, address, length);
            } else {
                getpeername(fd, (struct sockaddr *)&peer, &peerSize);
            }
            char host[INET6_ADDRSTRLEN] = {};
            unsigned port = 0;
            if (peer.ss_family == AF_INET) {
                auto *v4 = (struct sockaddr_in *)&peer;
                inet_ntop(AF_INET, &v4->sin_addr, host, sizeof(host));
                port = ntohs(v4->sin_port);
            } else if (peer.ss_family == AF_INET6) {
                auto *v6 = (struct sockaddr_in6 *)&peer;
                inet_ntop(AF_INET6, &v6->sin6_addr, host, sizeof(host));
                port = ntohs(v6->sin6_port);
            }
            NSDictionary *info = @{@"identity": identity, @"name": displayName,
                @"direction": @(direction), @"host": [NSString stringWithUTF8String:host], @"port": @(port), @"pid": @(getpid()), @"hooks": @(hooksReady.load()), @"extraHooks": @(additionalHooks.load())};
            uint64_t version = generation.load();
            nextRefresh.store(now + 1.0);
            dispatch_async(worker, ^{
                @autoreleasepool {
                    // IPC never runs on the app's network or UI thread.
                    inside = true;
                    @try {
                        NSDictionary *reply = NSRequestPolicy(info);
                        NSApplyReply(reply, version);
                    } @catch (NSException *exception) {
                        mask.store(NSUnknown);
                    }
                    inside = false;
                    busy.store(false);
                }
            });
        }
    }
    // Expire stale allows even if the broker hangs or SpringBoard restarts.
    bool allowed = NSCachedAllows(mask.load(), direction,
                                  NSProcessInfo.processInfo.systemUptime, lastReply.load());
    inside = false;
    errno = allowed ? savedErrno : EACCES;
    return allowed;
}
