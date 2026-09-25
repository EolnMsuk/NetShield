#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <errno.h>
#import <unistd.h>
#import <notify.h>
#import <string.h>
#import <atomic>
#import "Shared.h"

static std::atomic<int> mask{NSUnknown};
static std::atomic<bool> busy{false};
static std::atomic<uint64_t> generation{0};
static NSString *identity, *displayName;
static dispatch_queue_t worker;
static CPDistributedMessagingCenter *center;
static int changeToken;
static std::atomic<double> nextRefresh{0};
static std::atomic<double> lastReply{0};
static thread_local bool inside = false;

void NSStartClient(void) {
    NSBundle *bundle = NSBundle.mainBundle;
    identity = bundle.bundleIdentifier ?: [@"exec:" stringByAppendingString:NSProcessInfo.processInfo.arguments.firstObject ?: @"unknown"];
    displayName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"] ?: NSProcessInfo.processInfo.processName;
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
    // Do not touch files, pipes or AF_UNIX IPC. No fd cache: descriptors are reused.
    if (getsockname(fd, (struct sockaddr *)&local, &size) != 0 ||
        (local.ss_family != AF_INET && local.ss_family != AF_INET6)) {
        errno = savedErrno;
        return true;
    }
    inside = true;
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
                @"direction": @(direction), @"host": [NSString stringWithUTF8String:host], @"port": @(port), @"pid": @(getpid())};
            uint64_t version = generation.load();
            nextRefresh.store(now + 1.0);
            dispatch_async(worker, ^{
                @autoreleasepool {
                    // IPC never runs on the app's network or UI thread.
                    inside = true;
                    @try {
                        if (!center) center = NSCreateCenter();
                        NSDictionary *reply = [center sendMessageAndReceiveReplyName:@"check" userInfo:info];
                        if (generation.load() == version) {
                            NSNumber *value = reply[@"mask"], *active = reply[@"enabled"];
                            BOOL valid = [value isKindOfClass:NSNumber.class] && [active isKindOfClass:NSNumber.class];
                            // Store effective policy as one atomic value: no torn enable/mask state.
                            mask.store(valid && !active.boolValue ? NSBoth :
                                       (valid && NSValidRule(value.intValue) ? value.intValue : NSUnknown));
                            lastReply.store(valid ? NSProcessInfo.processInfo.systemUptime : 0);
                        }
                    } @catch (NSException *exception) {
                        mask.store(NSUnknown);
                        center = nil;
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
