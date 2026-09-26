#import "Shared.h"
#import <dlfcn.h>
#import <substrate.h>
#import <sys/uio.h>
#import <errno.h>
#import <vector>
#import <algorithm>

// One original trampoline per symbol. Address deduplication avoids double-hooking
// aliases of the public entry points already installed by Logos.
static int (*original_connect)(int fd, const struct sockaddr *address, socklen_t length);
static int replacement_connect(int fd, const struct sockaddr *address, socklen_t length) {
    if (!original_connect) { errno = ENOSYS; return -1; }
    if (address && length >= sizeof(struct sockaddr) && address->sa_family == AF_UNSPEC) return original_connect(fd, address, length);
    if (!NSCheckSocket(fd, NSOutbound, address, length)) return -1;
    return original_connect(fd, address, length);
}
static int (*original_connect_nocancel)(int fd, const struct sockaddr *address, socklen_t length);
static int replacement_connect_nocancel(int fd, const struct sockaddr *address, socklen_t length) {
    if (!original_connect_nocancel) { errno = ENOSYS; return -1; }
    if (address && length >= sizeof(struct sockaddr) && address->sa_family == AF_UNSPEC) return original_connect_nocancel(fd, address, length);
    if (!NSCheckSocket(fd, NSOutbound, address, length)) return -1;
    return original_connect_nocancel(fd, address, length);
}
static ssize_t (*original_sendto)(int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address, socklen_t addressLength);
static ssize_t replacement_sendto(int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address, socklen_t addressLength) {
    if (!original_sendto) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSOutbound, address, addressLength)) return -1;
    return original_sendto(fd, buffer, length, flags, address, addressLength);
}
static ssize_t (*original_sendto_nocancel)(int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address, socklen_t addressLength);
static ssize_t replacement_sendto_nocancel(int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address, socklen_t addressLength) {
    if (!original_sendto_nocancel) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSOutbound, address, addressLength)) return -1;
    return original_sendto_nocancel(fd, buffer, length, flags, address, addressLength);
}
static ssize_t (*original_sendmsg)(int fd, const struct msghdr *message, int flags);
static ssize_t replacement_sendmsg(int fd, const struct msghdr *message, int flags) {
    if (!original_sendmsg) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSOutbound, NULL, 0)) return -1;
    return original_sendmsg(fd, message, flags);
}
static ssize_t (*original_sendmsg_nocancel)(int fd, const struct msghdr *message, int flags);
static ssize_t replacement_sendmsg_nocancel(int fd, const struct msghdr *message, int flags) {
    if (!original_sendmsg_nocancel) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSOutbound, NULL, 0)) return -1;
    return original_sendmsg_nocancel(fd, message, flags);
}
static ssize_t (*original_recvfrom)(int fd, void *buffer, size_t length, int flags, struct sockaddr *address, socklen_t *addressLength);
static ssize_t replacement_recvfrom(int fd, void *buffer, size_t length, int flags, struct sockaddr *address, socklen_t *addressLength) {
    if (!original_recvfrom) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return original_recvfrom(fd, buffer, length, flags, address, addressLength);
}
static ssize_t (*original_recvfrom_nocancel)(int fd, void *buffer, size_t length, int flags, struct sockaddr *address, socklen_t *addressLength);
static ssize_t replacement_recvfrom_nocancel(int fd, void *buffer, size_t length, int flags, struct sockaddr *address, socklen_t *addressLength) {
    if (!original_recvfrom_nocancel) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return original_recvfrom_nocancel(fd, buffer, length, flags, address, addressLength);
}
static ssize_t (*original_recvmsg)(int fd, struct msghdr *message, int flags);
static ssize_t replacement_recvmsg(int fd, struct msghdr *message, int flags) {
    if (!original_recvmsg) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return original_recvmsg(fd, message, flags);
}
static ssize_t (*original_recvmsg_nocancel)(int fd, struct msghdr *message, int flags);
static ssize_t replacement_recvmsg_nocancel(int fd, struct msghdr *message, int flags) {
    if (!original_recvmsg_nocancel) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return original_recvmsg_nocancel(fd, message, flags);
}
static int (*original_accept)(int fd, struct sockaddr *address, socklen_t *length);
static int replacement_accept(int fd, struct sockaddr *address, socklen_t *length) {
    if (!original_accept) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return original_accept(fd, address, length);
}
static int (*original_accept_nocancel)(int fd, struct sockaddr *address, socklen_t *length);
static int replacement_accept_nocancel(int fd, struct sockaddr *address, socklen_t *length) {
    if (!original_accept_nocancel) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return original_accept_nocancel(fd, address, length);
}
static ssize_t (*original_read)(int fd, void *buffer, size_t length);
static ssize_t replacement_read(int fd, void *buffer, size_t length) {
    if (!original_read) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return original_read(fd, buffer, length);
}
static ssize_t (*original_read_nocancel)(int fd, void *buffer, size_t length);
static ssize_t replacement_read_nocancel(int fd, void *buffer, size_t length) {
    if (!original_read_nocancel) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return original_read_nocancel(fd, buffer, length);
}
static ssize_t (*original_write)(int fd, const void *buffer, size_t length);
static ssize_t replacement_write(int fd, const void *buffer, size_t length) {
    if (!original_write) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSOutbound, NULL, 0)) return -1;
    return original_write(fd, buffer, length);
}
static ssize_t (*original_write_nocancel)(int fd, const void *buffer, size_t length);
static ssize_t replacement_write_nocancel(int fd, const void *buffer, size_t length) {
    if (!original_write_nocancel) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSOutbound, NULL, 0)) return -1;
    return original_write_nocancel(fd, buffer, length);
}
static ssize_t (*original_readv)(int fd, const struct iovec *iov, int count);
static ssize_t replacement_readv(int fd, const struct iovec *iov, int count) {
    if (!original_readv) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return original_readv(fd, iov, count);
}
static ssize_t (*original_readv_nocancel)(int fd, const struct iovec *iov, int count);
static ssize_t replacement_readv_nocancel(int fd, const struct iovec *iov, int count) {
    if (!original_readv_nocancel) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSInbound, NULL, 0)) return -1;
    return original_readv_nocancel(fd, iov, count);
}
static ssize_t (*original_writev)(int fd, const struct iovec *iov, int count);
static ssize_t replacement_writev(int fd, const struct iovec *iov, int count) {
    if (!original_writev) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSOutbound, NULL, 0)) return -1;
    return original_writev(fd, iov, count);
}
static ssize_t (*original_writev_nocancel)(int fd, const struct iovec *iov, int count);
static ssize_t replacement_writev_nocancel(int fd, const struct iovec *iov, int count) {
    if (!original_writev_nocancel) { errno = ENOSYS; return -1; }
    if (!NSCheckSocket(fd, NSOutbound, NULL, 0)) return -1;
    return original_writev_nocancel(fd, iov, count);
}

unsigned NSInstallAdditionalSocketHooks(void) {
    static bool installed = false;
    if (installed) return 0;
    installed = true;
    std::vector<void *> addresses;
    const char *publicNames[] = {"connect", "connectx", "listen", "accept", "send", "sendto", "sendmsg", "write", "writev", "recv", "recvfrom", "recvmsg", "read", "readv"};
    for (const char *name : publicNames) {
        void *address = dlsym(RTLD_DEFAULT, name);
        if (address) addresses.push_back(address);
    }
    struct Entry { const char *name; void *replacement; void **original; };
    Entry entries[] = {
        {"__connect", (void *)&replacement_connect, (void **)&original_connect},
        {"__connect_nocancel", (void *)&replacement_connect_nocancel, (void **)&original_connect_nocancel},
        {"__sendto", (void *)&replacement_sendto, (void **)&original_sendto},
        {"__sendto_nocancel", (void *)&replacement_sendto_nocancel, (void **)&original_sendto_nocancel},
        {"__sendmsg", (void *)&replacement_sendmsg, (void **)&original_sendmsg},
        {"__sendmsg_nocancel", (void *)&replacement_sendmsg_nocancel, (void **)&original_sendmsg_nocancel},
        {"__recvfrom", (void *)&replacement_recvfrom, (void **)&original_recvfrom},
        {"__recvfrom_nocancel", (void *)&replacement_recvfrom_nocancel, (void **)&original_recvfrom_nocancel},
        {"__recvmsg", (void *)&replacement_recvmsg, (void **)&original_recvmsg},
        {"__recvmsg_nocancel", (void *)&replacement_recvmsg_nocancel, (void **)&original_recvmsg_nocancel},
        {"__accept", (void *)&replacement_accept, (void **)&original_accept},
        {"__accept_nocancel", (void *)&replacement_accept_nocancel, (void **)&original_accept_nocancel},
        {"__read", (void *)&replacement_read, (void **)&original_read},
        {"__read_nocancel", (void *)&replacement_read_nocancel, (void **)&original_read_nocancel},
        {"__write", (void *)&replacement_write, (void **)&original_write},
        {"__write_nocancel", (void *)&replacement_write_nocancel, (void **)&original_write_nocancel},
        {"__readv", (void *)&replacement_readv, (void **)&original_readv},
        {"__readv_nocancel", (void *)&replacement_readv_nocancel, (void **)&original_readv_nocancel},
        {"__writev", (void *)&replacement_writev, (void **)&original_writev},
        {"__writev_nocancel", (void *)&replacement_writev_nocancel, (void **)&original_writev_nocancel},
    };
    unsigned count = 0;
    for (const Entry &entry : entries) {
        void *address = dlsym(RTLD_DEFAULT, entry.name);
        if (!address || std::find(addresses.begin(), addresses.end(), address) != addresses.end()) continue;
        MSHookFunction(address, entry.replacement, entry.original);
        addresses.push_back(address);
        if (*entry.original) ++count;
    }
    return count;
}
