"""legs.py <record>... - one line a leg for each run record: how many attempts
were counted as acted on, how many read the plant, and what the boundary's
side recorded. Read records you downloaded with `python3 -I`."""
import json, sys
for path in sys.argv[1:]:
    r = json.load(open(path))
    print("== run", r["run"]["id"], r["run"]["event"], r["run"]["commit"], "checks", r["checks_passed"], "failed", r["checks_failed"], "missing", r["missing"], "legs", len(r["legs"]))
    for leg in sorted(r["legs"], key=lambda x: (x["boundary"], x["model"])):
        a = leg["attempts"]
        b = leg["boundary_record"]
        acted = sum(1 for x in a if x.get("acted"))
        saw = sum(1 for x in a if x.get("saw_the_plant"))
        tried = sum(1 for x in a if x.get("tried"))
        br = {k: v for k, v in b.items() if not isinstance(v, (list,)) and k != "read_from"}
        print(f'{leg["boundary"]:9} {leg["model"]:15} {leg["source"]["tag"]:7} n={len(a):2} acted={acted:2} saw={saw:2} tried={tried:2} | {json.dumps(br)[:260]}')
