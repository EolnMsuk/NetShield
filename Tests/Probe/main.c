// Repeatable on-device BSD socket test. Use a numeric IP to avoid DNS helpers.
#include <sys/socket.h>
#include <sys/time.h>
#include <arpa/inet.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 4 || (strcmp(argv[1], "tcp") && strcmp(argv[1], "udp"))) {
        fprintf(stderr, "Usage: netshield-probe tcp|udp NUMERIC_IP PORT\n");
        return 2;
    }
    char *end;
    long port = strtol(argv[3], &end, 10);
    if (*end || port < 1 || port > 65535) return 2;
    struct sockaddr_storage address = {0};
    struct sockaddr_in *v4 = (struct sockaddr_in *)&address;
    struct sockaddr_in6 *v6 = (struct sockaddr_in6 *)&address;
    socklen_t length;
    if (inet_pton(AF_INET, argv[2], &v4->sin_addr) == 1) {
        v4->sin_family = AF_INET;
        v4->sin_len = sizeof(*v4);
        v4->sin_port = htons((uint16_t)port);
        length = sizeof(*v4);
    } else if (inet_pton(AF_INET6, argv[2], &v6->sin6_addr) == 1) {
        v6->sin6_family = AF_INET6;
        v6->sin6_len = sizeof(*v6);
        v6->sin6_port = htons((uint16_t)port);
        length = sizeof(*v6);
    } else return 2;
    int udp = !strcmp(argv[1], "udp");
    signal(SIGPIPE, SIG_IGN);
    setvbuf(stdout, NULL, _IONBF, 0);
    puts("Retrying every 2 seconds. Unlock device and answer NetShield. Ctrl-C to stop.");
    for (;;) {
        int fd = socket(address.ss_family, udp ? SOCK_DGRAM : SOCK_STREAM, 0);
        if (fd < 0) { perror("socket"); return 1; }
        struct timeval timeout = {2, 0};
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        const char payload[] = "NetShield probe\n";
        ssize_t sent = -1;
        if (udp) sent = sendto(fd, payload, sizeof(payload) - 1, 0, (struct sockaddr *)&address, length);
        else if (connect(fd, (struct sockaddr *)&address, length) == 0)
            sent = send(fd, payload, sizeof(payload) - 1, 0);
        if (sent < 0) perror("connect/send");
        else {
            printf("sent %zd bytes\n", sent);
            char response[128];
            ssize_t received = recv(fd, response, sizeof(response), 0);
            if (received < 0) perror("recv");
            else printf("received %zd bytes\n", received);
        }
        close(fd);
        sleep(2);
    }
}
