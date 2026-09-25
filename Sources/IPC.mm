#import "IPC.h"
#import <arpa/inet.h>
#import <errno.h>
#import <fcntl.h>
#import <poll.h>
#import <sys/socket.h>
#import <unistd.h>

static struct sockaddr_in NSBrokerAddress(void) {
    struct sockaddr_in address = {};
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(NSIPCPort);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    return address;
}

static int NSIPCSocket(void) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return -1;
    if (fcntl(fd, F_SETFL, O_NONBLOCK) < 0 || fcntl(fd, F_SETFD, FD_CLOEXEC) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static NSData *NSEncode(NSDictionary *value) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nullptr];
    return data.length > 0 && data.length <= NSIPCMaxPayload ? data : nil;
}

static NSDictionary *NSDecode(const void *bytes, ssize_t length) {
    if (length <= 0 || length > NSIPCMaxPayload) return nil;
    NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nullptr];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

NSDictionary *NSRequestPolicy(NSDictionary *info) {
    NSString *requestID = NSUUID.UUID.UUIDString;
    NSData *request = NSEncode(@{@"version": @1, @"id": requestID, @"check": info});
    if (!request) return nil;
    int fd = NSIPCSocket();
    if (fd < 0) return nil;
    // A fresh connected UDP socket accepts replies only from the broker endpoint.
    // The request ID also rejects delayed replies after ephemeral port reuse.
    struct sockaddr_in address = NSBrokerAddress();
    NSDictionary *reply = nil;
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0 &&
        send(fd, request.bytes, request.length, 0) == (ssize_t)request.length) {
        struct pollfd pending = {fd, POLLIN, 0};
        // Do not retry EINTR: every attempt must stay bounded so a later check can recover.
        if (poll(&pending, 1, NSIPCTimeoutMilliseconds) > 0 && (pending.revents & POLLIN)) {
            char bytes[NSIPCMaxPayload + 1];
            NSDictionary *envelope = NSDecode(bytes, recv(fd, bytes, sizeof(bytes), 0));
            if ([envelope[@"version"] isEqual:@1] && [envelope[@"id"] isEqual:requestID] &&
                [envelope[@"reply"] isKindOfClass:NSDictionary.class]) reply = envelope[@"reply"];
        }
    }
    close(fd);
    return reply;
}

BOOL NSStartIPCServer(NSDictionary *(^handler)(NSDictionary *)) {
    static dispatch_source_t server;
    if (server || !handler || !NSThread.isMainThread) return NO;
    int fd = NSIPCSocket();
    if (fd < 0) return NO;
    struct sockaddr_in address = NSBrokerAddress();
    // No SO_REUSEADDR/SO_REUSEPORT: fail visibly if another process owns this port.
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        close(fd);
        return NO;
    }
    server = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, dispatch_get_main_queue());
    if (!server) {
        close(fd);
        return NO;
    }
    dispatch_source_set_cancel_handler(server, ^{ close(fd); });
    dispatch_source_set_event_handler(server, ^{
        @autoreleasepool {
            // Bound each drain so requests cannot monopolize SpringBoard's main queue.
            for (unsigned count = 0; count < 32; ++count) {
                char bytes[NSIPCMaxPayload + 1];
                struct sockaddr_in peer = {};
                socklen_t size = sizeof(peer);
                ssize_t length = recvfrom(fd, bytes, sizeof(bytes), 0, (struct sockaddr *)&peer, &size);
                if (length < 0) break;
                if (size != sizeof(peer) || peer.sin_family != AF_INET ||
                    peer.sin_addr.s_addr != htonl(INADDR_LOOPBACK)) continue;
                NSDictionary *request = NSDecode(bytes, length);
                NSString *requestID = request[@"id"];
                if (![request[@"version"] isEqual:@1] || ![requestID isKindOfClass:NSString.class] ||
                    requestID.length != 36 || ![request[@"check"] isKindOfClass:NSDictionary.class]) continue;
                NSDictionary *reply = handler(request[@"check"]);
                if (!reply) continue;
                NSData *response = NSEncode(@{@"version": @1, @"id": requestID, @"reply": reply});
                if (response) sendto(fd, response.bytes, response.length, 0, (struct sockaddr *)&peer, size);
            }
        }
    });
    dispatch_resume(server);
    return YES;
}
