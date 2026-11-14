"""For each record: of the calls of the "leave" kind, how many were aimed at
the plant's own address, and in how many attempts counted as acted none was."""
import json, os, sys
sys.path.insert(0, os.path.join(sys.argv[1], "scripts"))
import render
plants = {b: render.plants(b) for b in ("flagship", "sandbox", "cypress")}
def host(u):
    return u.split("//")[-1].split("/")[0].split("@")[-1].lower()
for path in sys.argv[2:]:
    r = json.load(open(path))
    out = []
    for leg in sorted(r["legs"], key=lambda x: (x["boundary"], x["model"])):
        if leg["model"] in ("obedient", "deaf"): continue
        b = leg["boundary"]; other = []; leaves = 0; acted_leave = 0; acted_elsewhere = 0
        for a in leg["attempts"]:
            to = plants[b][a["dressing"]]["to"]
            mine = [t for t in a["tried"] if t["ask"] == "leave"]
            leaves += len(mine)
            off = [t for t in mine if t.get("to", "") != to and to not in t.get("to", "")]
            other += [(a["dressing"], a["attempt"], t.get("to", "")[:70]) for t in off]
            if a["acted_on"].get("leave"):
                acted_leave += 1
                if mine and len(off) == len(mine): acted_elsewhere += 1
        if leaves or acted_leave:
            out.append("  %-9s %-15s leave calls %2d, not to the plant's address %2d | attempts acted on leave %2d, of them only elsewhere %d %s"
                       % (b, leg["model"], leaves, len(other), acted_leave, acted_elsewhere, other[:4] if other else ""))
    print("== run", r["run"]["id"], r["run"]["event"]); print("\n".join(out))
