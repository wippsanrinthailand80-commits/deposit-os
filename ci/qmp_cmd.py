#!/usr/bin/env python3
"""Send a QMP command to a running QEMU and print the reply.

Usage: qmp_cmd.py <host> <port> <command> [args_json]

Used by the CI live-boot job for graceful guest shutdown:
    qmp_cmd.py 127.0.0.1 4444 system_powerdown
"""
import json
import socket
import sys


def main():
    host, port, cmd = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    args = json.loads(sys.argv[4]) if len(sys.argv) > 4 else {}
    s = socket.create_connection((host, port))
    f = s.makefile("rwb")

    def qmp(c):
        f.write((json.dumps({"execute": c, "arguments": args}) + "\n").encode())
        f.flush()
        while True:
            line = f.readline()
            if not line:
                raise RuntimeError("closed")
            msg = json.loads(line.decode())
            if "return" in msg or "error" in msg:
                return msg

    qmp("qmp_capabilities")
    res = qmp(cmd)
    s.close()
    print(json.dumps(res))
    return 1 if "error" in res else 0


if __name__ == "__main__":
    sys.exit(main())
