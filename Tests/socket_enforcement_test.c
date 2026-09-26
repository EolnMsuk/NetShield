#include "../Sources/SocketEnforcement.h"
#include <arpa/inet.h>
#include <assert.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>

static void tcp_pair(int pair[2]) {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    assert(listener >= 0);
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    assert(bind(listener, (struct sockaddr *)&address, sizeof(address)) == 0);
    socklen_t size = sizeof(address);
    assert(getsockname(listener, (struct sockaddr *)&address, &size) == 0);
    assert(listen(listener, 1) == 0);
    pair[0] = socket(AF_INET, SOCK_STREAM, 0);
    assert(pair[0] >= 0);
    assert(connect(pair[0], (struct sockaddr *)&address, size) == 0);
    pair[1] = accept(listener, NULL, NULL);
    assert(pair[1] >= 0);
    close(listener);
}
static void transfer(int sender, int receiver) {
    assert(send(sender, "x", 1, 0) == 1);
    struct pollfd waiting = {receiver, POLLIN, 0};
    assert(poll(&waiting, 1, 1000) > 0);
    char byte = 0;
    assert(recv(receiver, &byte, 1, 0) == 1 && byte == 'x');
}
int main(void) {
    alarm(10); // Fail instead of hanging CI if a socket assertion stops making progress.
    signal(SIGPIPE, SIG_IGN);
    int pair[2];
    tcp_pair(pair);
    transfer(pair[0], pair[1]);
    assert(NSShutdownBlockedSocket(pair[0], NSShutdownNone) == 0);
    transfer(pair[0], pair[1]);
    errno = EAGAIN;
    assert(NSShutdownBlockedSocket(pair[0], NSShutdownBoth) == 0);
    assert(errno == EAGAIN);
    assert(fcntl(pair[0], F_GETFD) >= 0); // App-owned fd was not closed.
    assert(send(pair[0], "x", 1, 0) == -1); // No hooks: the kernel enforces this.
    char byte;
    assert(recv(pair[0], &byte, 1, 0) == 0);
    close(pair[0]); close(pair[1]);
    tcp_pair(pair);
    assert(NSShutdownBlockedSocket(pair[0], NSShutdownReceive) == 0);
    transfer(pair[0], pair[1]); // Incoming-only block still permits sends.
    assert(recv(pair[0], &byte, 1, 0) == 0);
    close(pair[0]); close(pair[1]);
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    assert(NSShutdownBlockedSocket(pair[0], NSShutdownBoth) == -1);
    transfer(pair[0], pair[1]); // Local IPC remains intact.
    close(pair[0]); close(pair[1]);
    assert(pipe(pair) == 0);
    assert(NSShutdownBlockedSocket(pair[0], NSShutdownBoth) == -1);
    assert(write(pair[1], "x", 1) == 1);
    assert(read(pair[0], &byte, 1) == 1);
    close(pair[0]); close(pair[1]);
    puts("Kernel socket shutdown and non-IP preservation tests passed");
    return 0;
}
