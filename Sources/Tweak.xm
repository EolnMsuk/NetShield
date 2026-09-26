#import <sys/socket.h>
#import <sys/uio.h>
#import <unistd.h>
#import <errno.h>
#import "Shared.h"

%group SocketHooks
%hookf(int, connect, int fd, const struct sockaddr *address, socklen_t length) {
    if (address && address->sa_family == AF_UNSPEC) return %orig; // UDP disconnect
    if (!NSCheckSocket(fd, NSOutbound, address, length)) return -1;
    return %orig;
}
%hookf(int, connectx, int fd, const sa_endpoints_t *endpoints, sae_associd_t assoc, unsigned int flags, const struct iovec *iov, unsigned int count, size_t *length, sae_connid_t *connection) {
    if (!NSCheckSocket(fd, NSOutbound, endpoints ? endpoints->sae_dstaddr : NULL,
                       endpoints ? endpoints->sae_dstaddrlen : 0)) return -1;
    return %orig;
}
%hookf(int, listen, int fd, int backlog) {
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return %orig;
}
%hookf(int, accept, int fd, struct sockaddr *address, socklen_t *length) {
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return %orig;
}
%hookf(ssize_t, send, int fd, const void *buffer, size_t length, int flags) {
    if (!NSCheckSocket(fd, NSOutbound, NULL, 0)) return -1;
    return %orig;
}
%hookf(ssize_t, sendto, int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address, socklen_t addressLength) {
    if (!NSCheckSocket(fd, NSOutbound, address, addressLength)) return -1;
    return %orig;
}
%hookf(ssize_t, sendmsg, int fd, const struct msghdr *message, int flags) {
    if (!NSCheckSocket(fd, NSOutbound, message ? (const struct sockaddr *)message->msg_name : NULL,
                       message ? message->msg_namelen : 0)) return -1;
    return %orig;
}
%hookf(ssize_t, write, int fd, const void *buffer, size_t length) {
    if (!NSCheckSocket(fd, NSOutbound, NULL, 0)) return -1;
    return %orig;
}
%hookf(ssize_t, writev, int fd, const struct iovec *iov, int count) {
    if (!NSCheckSocket(fd, NSOutbound, NULL, 0)) return -1;
    return %orig;
}
%hookf(ssize_t, recv, int fd, void *buffer, size_t length, int flags) {
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return %orig;
}
%hookf(ssize_t, recvfrom, int fd, void *buffer, size_t length, int flags, struct sockaddr *address, socklen_t *addressLength) {
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return %orig;
}
%hookf(ssize_t, recvmsg, int fd, struct msghdr *message, int flags) {
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return %orig;
}
%hookf(ssize_t, read, int fd, void *buffer, size_t length) {
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return %orig;
}
%hookf(ssize_t, readv, int fd, const struct iovec *iov, int count) {
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return %orig;
}
%end

%ctor {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if ([bundle isEqualToString:@"com.apple.springboard"]) {
            dispatch_async(dispatch_get_main_queue(), ^{ NSStartBroker(); });
        } else if (![bundle isEqualToString:@"com.apple.Preferences"]) {
            // Keep Settings available for recovery. Filter Apple apps as well as third-party apps.
            // The injection filter remains app-scoped, not a blanket daemon injection.
            NSStartClient();
            %init(SocketHooks);
            unsigned extraHooks = NSInstallAdditionalSocketHooks();
            NSClientHooksReady(extraHooks);
        }
    }
}
