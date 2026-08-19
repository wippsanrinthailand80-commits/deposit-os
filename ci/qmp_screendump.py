#!/usr/bin/env python3
"""Minimal QEMU QMP client: connect, negotiate, and screendump to a PNG.

Usage: qmp_screendump.py <out.png> [host] [port]

Used by the CI live-boot job to grab frames of the running Deposit OS VM
(boot screen, GUI, terminal running AQA) without any display attached.
"""
import json
import socket
import sys


def main():
    out = sys.argv[1]
    host = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    port = int(sys.argv[3]) if len(sys.argv) > 3 else 4444

    s = socket.create_connection((host, port))
    f = s.makefile("rwb")

    def qmp(cmd):
        f.write((json.dumps(cmd) + "\n").encode())
        f.flush()
        while True:
            line = f.readline()
            if not line:
                raise RuntimeError("QMP connection closed")
            msg = json.loads(line.decode())
            # ignore async events / greeting; wait for a command reply
            if "return" in msg or "error" in msg:
                return msg

    qmp({"execute": "qmp_capabilities"})
    # QEMU defaults to PPM; ask for PNG so the Actions Summary can embed it.
    res = qmp({"execute": "screendump", "arguments": {"filename": out, "format": "png"}})
    s.close()
    if "error" in res:
        sys.stderr.write("screendump error: %r\n" % res["error"])
        return 1
    sys.stderr.write("screendump -> %s\n" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
