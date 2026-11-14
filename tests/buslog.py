#!/usr/bin/python3
"""Reads a dbus-monitor log of org.freedesktop.Notifications (matrix cases).

    tests/buslog.py LOG                    one line per event
    tests/buslog.py LOG closed ID SUMMARY  "<reason> <seconds>": the reason of
                                           the NotificationClosed for ID and
                                           the time since the last Notify
                                           call with that summary
    tests/buslog.py LOG count ID           number of NotificationClosed for ID

All times come from the `time=` fields of the log, so they share one clock.
"""
import re
import sys

HEAD = re.compile(r"^(method call|signal) time=([\d.]+) .*member=(\w+)")
ARG = re.compile(r"^   (string|uint32|int32) (.*)$")  # top-level arguments only


def events(path):
    out, cur = [], None
    for line in open(path, errors="replace"):
        m = HEAD.match(line)
        if m:
            cur = {"kind": m.group(1), "time": float(m.group(2)), "member": m.group(3), "args": []}
            out.append(cur)
            continue
        if cur is None:
            continue
        a = ARG.match(line.rstrip("\n"))
        if a:
            value = a.group(2)
            if a.group(1) == "string":
                value = value[1:-1] if value.startswith('"') else value
            else:
                value = int(value)
            cur["args"].append(value)
    return out


def describe(e):
    a = e["args"]
    if e["member"] == "Notify" and len(a) >= 5:
        return f"notify  {e['time']:.3f} app={a[0]!r} replaces={a[1]} summary={a[3]!r}"
    if e["member"] == "NotificationClosed" and len(a) >= 2:
        return f"closed  {e['time']:.3f} id={a[0]} reason={a[1]}"
    if e["member"] == "ActionInvoked" and len(a) >= 2:
        return f"action  {e['time']:.3f} id={a[0]} key={a[1]!r}"
    if e["member"] == "CloseNotification" and a:
        return f"close   {e['time']:.3f} id={a[0]}"
    return f"{e['member']:7} {e['time']:.3f} {a}"


evs = events(sys.argv[1])
if len(sys.argv) == 2:
    for e in evs:
        print(describe(e))
elif sys.argv[2] == "closed":
    nid, summary = int(sys.argv[3]), sys.argv[4]
    sent = [e["time"] for e in evs if e["member"] == "Notify" and len(e["args"]) >= 5 and e["args"][3] == summary]
    closed = [e for e in evs if e["member"] == "NotificationClosed" and e["args"][:1] == [nid]]
    if not sent or not closed:
        print("none")
    else:
        print(f"{closed[0]['args'][1]} {closed[0]['time'] - sent[-1]:.2f}")
elif sys.argv[2] == "count":
    nid = int(sys.argv[3])
    print(sum(1 for e in evs if e["member"] == "NotificationClosed" and e["args"][:1] == [nid]))
else:
    sys.exit(__doc__)
