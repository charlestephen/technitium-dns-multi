#!/usr/bin/env python3
"""Stand-in for Technitium in the dnsdist test.

Listens for DNS over UDP with the PROXY protocol v2 header that dnsdist sends, and answers according to the
client address carried in that header, like per-client block lists do:
  127.0.0.2 -> not blocked (answers with 9.9.9.9)
  anyone else -> blocked (NXDOMAIN)
The name "localhost" is always answered, for dnsdist's backend health check.
"""
import socket
import struct

SIG = b"\r\n\r\n\x00\r\nQUIT\n"


def parse_proxy(data):
    if data[:12] != SIG:
        return None, data
    _, fam, length = struct.unpack("!BBH", data[12:16])
    block = data[16:16 + length]
    if fam >> 4 == 1:
        src = socket.inet_ntoa(block[0:4])
    elif fam >> 4 == 2:
        src = socket.inet_ntop(socket.AF_INET6, block[0:16])
    else:
        src = "?"
    return src, data[16 + length:]


def question(dns):
    i, labels = 12, []
    while dns[i]:
        n = dns[i]
        labels.append(dns[i + 1:i + 1 + n].decode())
        i += n + 1
    return ".".join(labels), i + 1


def main():
    log = open("/tmp/backend.log", "a", buffering=1)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 5300))
    while True:
        data, addr = sock.recvfrom(4096)
        src, dns = parse_proxy(data)
        if len(dns) < 12:
            continue
        name, end = question(dns)
        qtype = struct.unpack("!H", dns[end:end + 2])[0]
        q = dns[12:end + 4]
        allowed = name == "localhost" or src == "127.0.0.2"
        log.write(f"{name} {src} {'ANSWER' if allowed else 'NXDOMAIN'}\n")
        if allowed and qtype == 1:
            resp = dns[:2] + struct.pack("!HHHHH", 0x8180, 1, 1, 0, 0) + q + b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 300, 4) + bytes([9, 9, 9, 9])
        elif allowed:
            resp = dns[:2] + struct.pack("!HHHHH", 0x8180, 1, 0, 0, 0) + q
        else:
            resp = dns[:2] + struct.pack("!HHHHH", 0x8183, 1, 0, 0, 0) + q
        sock.sendto(resp, addr)


if __name__ == "__main__":
    main()
