#import "../Sources/IPC.h"
#import <arpa/inet.h>
#import <assert.h>
#import <poll.h>
#import <stdio.h>
#import <stdlib.h>
#import <sys/socket.h>
#import <unistd.h>

static void expectNoReply(NSData *data) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    assert(fd >= 0);
    struct sockaddr_in address = {};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(NSIPCPort);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    assert(connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0);
    assert(send(fd, data.bytes, data.length, 0) == (ssize_t)data.length);
    struct pollfd pending = {fd, POLLIN, 0};
    assert(poll(&pending, 1, NSIPCTimeoutMilliseconds) == 0);
    close(fd);
}

static void expectBadReplyRejected(NSData *response) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    assert(fd >= 0);
    struct sockaddr_in address = {};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(NSIPCPort);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    assert(bind(fd, (struct sockaddr *)&address, sizeof(address)) == 0);
    // Startup must report a port collision instead of silently sharing the endpoint.
    assert(!NSStartIPCServer(^NSDictionary *(NSDictionary *info) { return info; }));
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        struct pollfd pending = {fd, POLLIN, 0};
        assert(poll(&pending, 1, 2000) > 0);
        char bytes[NSIPCMaxPayload + 1];
        struct sockaddr_in peer = {};
        socklen_t size = sizeof(peer);
        assert(recvfrom(fd, bytes, sizeof(bytes), 0, (struct sockaddr *)&peer, &size) > 0);
        assert(sendto(fd, response.bytes, response.length, 0, (struct sockaddr *)&peer, size) == (ssize_t)response.length);
        dispatch_semaphore_signal(finished);
    });
    assert(NSRequestPolicy(@{@"case": @"echo"}) == nil);
    assert(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0);
    close(fd);
}

int main(void) {
    @autoreleasepool {
        // A missing listener must fail closed, including before SpringBoard starts.
        assert(NSRequestPolicy(@{@"case": @"echo"}) == nil);
        expectBadReplyRejected([@"not JSON" dataUsingEncoding:NSUTF8StringEncoding]);
        expectBadReplyRejected([NSJSONSerialization dataWithJSONObject:
            @{@"version": @1, @"id": @"wrong-request-id", @"reply": @{@"mask": @3, @"enabled": @YES}}
            options:0 error:nullptr]);
        assert(!NSStartIPCServer(nil));
        assert(NSStartIPCServer(^NSDictionary *(NSDictionary *info) {
            assert(NSThread.isMainThread);
            if ([info[@"case"] isEqual:@"drop"]) return nil;
            return @{@"mask": @3, @"enabled": @YES, @"echo": info};
        }));
        assert(!NSStartIPCServer(^NSDictionary *(NSDictionary *info) { return info; }));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC),
                       dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            fputs("IPC test timed out\n", stderr);
            exit(1);
        });
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            @autoreleasepool {
                NSDictionary *info = @{@"case": @"echo", @"identity": @"com.netshield.test"};
                assert([NSRequestPolicy(info)[@"echo"] isEqual:info]);
                double started = NSProcessInfo.processInfo.systemUptime;
                assert(NSRequestPolicy(@{@"case": @"drop"}) == nil);
                assert(NSProcessInfo.processInfo.systemUptime - started < 2.0);
                assert([NSRequestPolicy(info)[@"mask"] isEqual:@3]);
                NSString *large = [@"x" stringByPaddingToLength:NSIPCMaxPayload + 1 withString:@"x" startingAtIndex:0];
                assert(NSRequestPolicy(@{@"large": large}) == nil);
                expectNoReply([@"not JSON" dataUsingEncoding:NSUTF8StringEncoding]);
                expectNoReply([@"[]" dataUsingEncoding:NSUTF8StringEncoding]);
                expectNoReply([large dataUsingEncoding:NSUTF8StringEncoding]);
                for (NSDictionary *invalid in @[
                    @{@"version": @2, @"id": NSUUID.UUID.UUIDString, @"check": info},
                    @{@"version": @1, @"id": @7, @"check": info},
                    @{@"version": @1, @"id": NSUUID.UUID.UUIDString, @"check": @[]}
                ]) {
                    expectNoReply([NSJSONSerialization dataWithJSONObject:invalid options:0 error:nullptr]);
                }
                assert([NSRequestPolicy(info)[@"echo"] isEqual:info]);
                puts("IPC round-trip, timeout/recovery and malformed-message tests passed");
                exit(0);
            }
        });
    }
    @autoreleasepool {
        // Keep the actual main thread running, just as SpringBoard does.
        [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) { (void)timer; }];
        [NSRunLoop.mainRunLoop run];
    }
    return 1;
}
