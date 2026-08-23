#!/usr/bin/env python3
"""Minimal QEMU QMP client: connect, negotiate, and screendump to a PNG.

Usage: qmp_screendump.py <out.png> [host] [qmp_port] [--vnc-poke vnc_port]

Used by the CI live-boot job to grab frames of the running Deposit OS VM.
QEMU bug workaround: without any VNC client having connected, the std-VGA
display surface can stay unmaterialized and `screendump` returns a blank
frame. --vnc-poke performs a minimal RFB handshake + full framebuffer
update request first, which forces the surface to exist.
"""
import json
import socket
import sys


def rfb_poke(host, port):
    """Minimal VNC client: handshake + one full FramebufferUpdateRequest."""
    s = socket.create_connection((host, port), timeout=10)
    s.settimeout(10)
    f = s.makefile("rb")

    def rd(n):
        b = f.read(n)
        if len(b) != n:
            raise RuntimeError("short read")
        return b

    ver = rd(12)
    s.sendall(b"RFB 003.008\n")
    ntypes = rd(1)[0]
    sec = rd(ntypes)
    if 1 not in sec:
        raise RuntimeError(f"no 'None' security type offered: {sec!r}")
    s.sendall(b"\x01")            # choose None
    res = rd(4)                   # SecurityResult
    if res != b"\x00\x00\x00\x00":
        raise RuntimeError(f"security handshake failed: {res!r}")
    s.sendall(b"\x01")            # ClientInit (shared)
    rd(24)                        # ServerInit header (w,h,pixelformat)
    nlen = int.from_bytes(rd(4), "big")
    rd(nlen)                      # name
    # Full (non-incremental) framebuffer update request
    s.sendall(b"\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00")
    # Drain at least the update message header (best-effort)
    try:
        t = rd(1)[0]
        if t == 0:
            rd(15)
            rects = int.from_bytes(rd(2), "big")
            for _ in range(min(rects, 64)):
                rd(12)
                enc = int.from_bytes(rd(4), "big")
                w = int.from_bytes(rd(2), "big"); h = int.from_bytes(rd(2), "big")
                _ = enc
                # cannot know encoded size generically; stop here — the point
                # was to make QEMU render, not to decode pixels.
                break
    except Exception:
        pass
    s.close()


def main():
    args = sys.argv[1:]
    out = args[0]
    host = args[1] if len(args) > 1 else "127.0.0.1"
    port = int(args[2]) if len(args) > 2 else 4444

    if "--vnc-poke" in args:
        vp = int(args[args.index("--vnc-poke") + 1])
        try:
            rfb_poke(host, vp)
            sys.stderr.write(f"vnc poke {host}:{vp} ok\n")
        except Exception as e:
            sys.stderr.write(f"vnc poke failed (continuing): {e}\n")

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
            if "return" in msg or "error" in msg:
                return msg

    qmp({"execute": "qmp_capabilities"})
    res = qmp({"execute": "screendump", "arguments": {"filename": out, "format": "png"}})
    s.close()
    if "error" in res:
        sys.stderr.write("screendump error: %r\n" % res["error"])
        return 1
    sys.stderr.write("screendump -> %s\n" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
