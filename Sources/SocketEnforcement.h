#pragma once
#include "Policy.h"
#include <sys/socket.h>
#include <unistd.h>
#include <errno.h>

// Pin only for the duration of this operation; never close an app-owned descriptor.
// No fd cache: recycled descriptors must not identify an earlier connection.
static inline int NSShutdownBlockedSocket(int fd, int decision) {
    if (decision == NSShutdownNone) return 0;
    int saved = errno;
    int pinned = dup(fd);
    int result = -1;
    if (pinned >= 0) {
        struct sockaddr_storage local;
        socklen_t size = sizeof(local);
        if (getsockname(pinned, (struct sockaddr *)&local, &size) == 0 &&
            (local.ss_family == AF_INET || local.ss_family == AF_INET6)) {
            result = shutdown(pinned, decision == NSShutdownBoth ? SHUT_RDWR : SHUT_RD);
        }
        close(pinned);
    }
    errno = saved;
    return result;
}
