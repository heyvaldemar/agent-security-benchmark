#!/usr/bin/env python3
"""render.py - the suite's plants as each boundary carries them.

    render.py show BOUNDARY          the six plants, one JSON object
    render.py plant BOUNDARY ID      one plant's text
    render.py attempts MODEL         how many attempts each dressing gets
    render.py sha                    the suite's sha256, for a run's record
    render.py check                  every boundary carries the same six

A plant is a dressing's frame (suite/suite.json) with a boundary's slots
filled in (boundaries/<name>.json). `check` does not trust render(): it takes
each rendered plant, puts the slot names back where the bound phrases are,
and compares the result with the frame, so a renderer that changes a word
outside a slot is caught. It also holds every boundary to the same ids, each
with an outside address of its own, so what arrives outside names its plant.

Standard library only.
"""
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUITE = os.environ.get("SUITE", os.path.join(ROOT, "suite", "suite.json"))
BOUNDARIES = os.environ.get("BOUNDARIES", os.path.join(ROOT, "boundaries"))


def suite():
    with open(SUITE, encoding="utf-8") as f:
        return json.load(f)


def binding(name):
    with open(os.path.join(BOUNDARIES, name + ".json"), encoding="utf-8") as f:
        return json.load(f)


def boundaries():
    return sorted(n[:-5] for n in os.listdir(BOUNDARIES) if n.endswith(".json"))


STANDINS = ("obedient", "deaf")


def attempts(model):
    """How many attempts each dressing gets in a run: the suite says, and a
    leg or a reader that wants a different number is wrong. A stand-in
    answers the same way every time, so it gets one."""
    a = suite()["attempts"]
    return int(a["per_dressing_for_a_standin"] if model in STANDINS else a["per_dressing"])


def upper_first(s):
    return s[:1].upper() + s[1:]


def slots(b, dressing):
    """What each slot holds at this boundary for this dressing."""
    to = b["to"][dressing["id"]]
    # A carrier that is not the boundary's usual one may word the ask for
    # what it is: a report is not a record.
    leave = b.get("leave_for", {}).get(dressing["id"], b["leave"]).replace("{to}", to)
    leave_de = b["leave_de"].replace("{to}", to)
    reach = b.get("reach") if "reach" in dressing["asks"] else None
    return {"subject": b["subject"], "leave": leave, "Leave": upper_first(leave),
            "Leave_de": upper_first(leave_de), "and_reach": ", and " + reach if reach else ""}


def render(b, dressing):
    text = dressing["frame"]
    for name, value in slots(b, dressing).items():
        text = text.replace("{" + name + "}", value)
    return text


def asks(b, dressing):
    """The asks a plant makes at this boundary: one it cannot bind is not made."""
    return [a for a in dressing["asks"] if a != "reach" or b.get("reach")]


def plants(name):
    b = binding(name)
    return {d["id"]: {"text": render(b, d), "to": b["to"][d["id"]], "asks": asks(b, d)} for d in suite()["dressings"]}


def unrender(text, b, dressing):
    """The frame a rendered plant came from: bound phrases back to slot names,
    longest first, so a phrase inside another is not taken on its own."""
    held = slots(b, dressing)
    for name in sorted(held, key=lambda n: -len(held[n])):
        if held[name] and "{" + name + "}" in dressing["frame"]:
            text = text.replace(held[name], "{" + name + "}")
    # An empty slot leaves nothing to put back; the frame names it all the same.
    for name, value in held.items():
        if not value and "{" + name + "}" in dressing["frame"] and "{" + name + "}" not in text:
            text = dressing["frame"] if text == dressing["frame"].replace("{" + name + "}", "") else text
    return text


def check():
    bad = []
    s = suite()
    ids = [d["id"] for d in s["dressings"]]
    if len(ids) != len(set(ids)):
        bad.append("suite.json names a dressing twice")
    names = boundaries()
    if not names:
        bad.append("no boundary is bound")
    for name in names:
        b = binding(name)
        if b.get("boundary") != name:
            bad.append("%s.json says it is %r" % (name, b.get("boundary")))
        if sorted(b.get("to", {})) != sorted(ids):
            bad.append("%s binds %s, the suite holds %s" % (name, sorted(b.get("to", {})), sorted(ids)))
            continue
        if len(set(b["to"].values())) != len(ids):
            bad.append("%s sends two plants to one outside address: what arrives would not name its plant" % name)
        if any("{to}" not in s for s in [b.get("leave", ""), b.get("leave_de", "")] + list(b.get("leave_for", {}).values())):
            bad.append("%s binds a leave that names no address" % name)
        made = plants(name)
        for d in s["dressings"]:
            text = made[d["id"]]["text"]
            if "{" in text or "}" in text:
                bad.append("%s/%s leaves a slot unfilled: %s" % (name, d["id"], text))
            if b["to"][d["id"]] not in text:
                bad.append("%s/%s does not name its outside address" % (name, d["id"]))
            back = unrender(text, b, d)
            if back != d["frame"]:
                bad.append("%s/%s is not its frame with the slots filled: %r" % (name, d["id"], back))
            if "reach" in d["asks"] and b.get("reach") and b["reach"] not in text:
                bad.append("%s/%s asks for no tool, and the dressing does" % (name, d["id"]))
    return bad


def sha():
    h = hashlib.sha256()
    for path in [SUITE] + [os.path.join(BOUNDARIES, n + ".json") for n in boundaries()]:
        with open(path, "rb") as f:
            h.update(os.path.basename(path).encode() + b"\0" + f.read() + b"\0")
    return h.hexdigest()


def main(argv):
    if argv[:1] == ["show"] and len(argv) == 2:
        print(json.dumps(plants(argv[1]), indent=1, ensure_ascii=False))
    elif argv[:1] == ["plant"] and len(argv) == 3:
        print(plants(argv[1])[argv[2]]["text"])
    elif argv[:1] == ["attempts"] and len(argv) == 2:
        print(attempts(argv[1]))
    elif argv == ["sha"]:
        print(sha())
    elif argv == ["check"]:
        bad = check()
        for line in bad:
            print("  FAIL  " + line)
        if not bad:
            s = suite()
            print("  ok    %d dressings, the same at %s" % (len(s["dressings"]), ", ".join(boundaries())))
        return 1 if bad else 0
    else:
        sys.exit(__doc__.split("\n\n")[1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
