import json, socket, sys, time

sock = sys.argv[1]
s = socket.socket(socket.AF_UNIX)
s.connect(sock)
st = {"buf": b"", "seq": 0}


def cmd(*a):
    st["seq"] += 1
    s.sendall(
        (json.dumps({"command": list(a), "request_id": st["seq"]}) + "\n").encode()
    )
    while True:
        while b"\n" not in st["buf"]:
            st["buf"] += s.recv(4096)
        line, st["buf"] = st["buf"].split(b"\n", 1)
        o = json.loads(line)
        if o.get("request_id") == st["seq"]:
            return o


def msg(t, *a):
    return cmd("script-message-to", t, *a)


time.sleep(1)
cmd("set_property", "aid", 2)
cmd("set_property", "sid", 1)
time.sleep(0.3)
cmd("seek", 3.3, "absolute")
time.sleep(0.4)
msg("clip", "menu-event", json.dumps({"type": "activate", "value": "start"}))
cmd("seek", 8.7, "absolute")
time.sleep(0.4)
msg("clip", "menu-event", json.dumps({"type": "activate", "value": "end"}))
time.sleep(0.2)
msg("clip", "menu-event", json.dumps({"type": "activate", "value": "create"}))
time.sleep(12)
cmd("quit")
