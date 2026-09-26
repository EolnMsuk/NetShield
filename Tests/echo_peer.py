"""Run on a LAN computer you control: python echo_peer.py tcp|udp [port]."""
import argparse
import socket

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("protocol", choices=["tcp", "udp"])
parser.add_argument("port", type=int, nargs="?", default=8765)
parser.add_argument("--ipv6", action="store_true")
args = parser.parse_args()
family = socket.AF_INET6 if args.ipv6 else socket.AF_INET
kind = socket.SOCK_STREAM if args.protocol == "tcp" else socket.SOCK_DGRAM
with socket.socket(family, kind) as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("::" if args.ipv6 else "0.0.0.0", args.port))
    print(f"Listening on {args.protocol} {args.port}; Ctrl-C to stop", flush=True)
    if args.protocol == "tcp":
        server.listen()
    while True:
        if args.protocol == "udp":
            data, peer = server.recvfrom(4096)
            print(peer, repr(data), flush=True)
            server.sendto(data, peer)
        else:
            connection, peer = server.accept()
            with connection:
                connection.settimeout(3)
                try:
                    data = connection.recv(4096)
                    print(peer, repr(data), flush=True)
                    connection.sendall(data)
                except (TimeoutError, ConnectionError):
                    pass
