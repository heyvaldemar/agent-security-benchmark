#!/usr/bin/env python3
"""numbers.py - a run's record, and the README's tables made from it.

    numbers.py record DIR > docs/runs/<run id>.json
                                   one record from a run's downloaded
                                   artifacts (`gh run download <id> -D DIR`):
                                   every job's results.json, their legs together
    numbers.py tables RECORD       the tables, as the README carries them
    numbers.py check [--write]     every block in README.md between
                                   <!-- numbers: docs/runs/<id>.json NAME --> and
                                   <!-- /numbers --> is what `tables` prints for
                                   that record; --write puts it there

One block is made from several records, joined with "+", and is named
`scheduled`: the one sentence that says "daily". It is refused unless every
record it names is a scheduled run's, with every check passed and the
signature made for it beside it, and there are at least two, of different
runs on different days; and the README may carry a word of cadence nowhere
else (AGENTS.md: such a word is written only after two scheduled runs in a
row have passed).

No number in the README is typed by hand (AGENTS.md). A record is what the
run's own jobs uploaded, kept in the repository under the run's id, so a
table can be made again from it by anyone and `scripts/validate.sh numbers`
can fail when the README says something the record does not.

Standard library only.
"""
import base64
import datetime
import glob
import hashlib
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STANDINS = ("obedient", "deaf")
BOUNDARIES = {"sandbox": "kubernetes-ai-agent-sandbox", "flagship": "kubernetes-air-gapped-ai-agent",
              "cypress": "cypress-cloud-triage-agent"}
WHERE = {"flagship": "At the flagship", "sandbox": "At the sandbox", "cypress": "In front of Cypress Cloud"}
BLOCK = re.compile(r"(<!-- numbers: (\S+) (\S+) -->\n)(.*?)(<!-- /numbers -->)", re.S)
MONTHS = ("January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
          "November", "December")
COUNT = {2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven"}
# A word of cadence. The README carries one only inside the block that the
# records of scheduled runs earn.
CADENCE = re.compile(r"\b(hourly|daily|nightly|weekly|monthly|every (?:hour|day|night|week|month))\b", re.I)


def expected():
    """The legs a run set out to make, from what its workflow says ran: the
    `needs` of the record's job (each job's result) and the models' list.
    None outside a workflow. A job that was skipped set out to make nothing;
    one that ran, failed or was cut short owed its legs."""
    ran, models = os.environ.get("LEGS_RAN"), os.environ.get("LEGS_MODELS")
    if not ran or not models:
        return None
    ran, models = json.loads(ran), json.loads(models)
    result = lambda job: (ran.get(job) or {}).get("result", "skipped")
    out = []
    if result("calibration") != "skipped":
        out += ["sandbox/obedient", "sandbox/deaf"]
    for boundary in ("flagship", "sandbox", "cypress"):
        if result(boundary) != "skipped":
            out += ["%s/%s" % (boundary, m) for m in models]
    return sorted(out)


def record(directory):
    parts = [json.load(open(p, encoding="utf-8"))
             for p in sorted(glob.glob(os.path.join(directory, "**", "results.json"), recursive=True))]
    owed = expected()
    if not parts and owed is None:
        sys.exit("no results.json under %s" % directory)
    if not parts:
        # A run in which no leg reported is still a run, and its record says so.
        run = os.environ.get("GITHUB_RUN_ID")
        repo = os.environ.get("GITHUB_REPOSITORY", "")
        return {"schema": 1, "run": {"id": int(run) if run else None,
                                     "url": "https://github.com/%s/actions/runs/%s" % (repo, run) if run else None,
                                     "event": os.environ.get("GITHUB_EVENT_NAME"),
                                     "commit": os.environ.get("GITHUB_SHA", "")[:7]},
                "suite_sha256": None, "legs": [], "expected": owed, "missing": owed,
                "checks_passed": 0, "checks_failed": 0}
    runs = {json.dumps(p["run"], sort_keys=True) for p in parts}
    suites = {p["suite_sha256"] for p in parts}
    if len(runs) != 1 or len(suites) != 1:
        sys.exit("the artifacts under %s are not one run's: %d runs, %d suites" % (directory, len(runs), len(suites)))
    legs = sorted((leg for p in parts for leg in p["legs"]), key=lambda x: (x["boundary"], x["model"]))
    # Every check a leg's job made, not only the reader's: admission's plants,
    # the controls, the release's own run. Each job wrote them beside its record.
    for p in glob.glob(os.path.join(directory, "**", "e2e-results-*.json"), recursive=True):
        job = json.load(open(p, encoding="utf-8"))
        for leg in legs:
            if (leg["boundary"], leg["model"]) == (job.get("boundary"), job.get("model")):
                leg["job_checks"] = job["checks"]
    checks = [c for leg in legs for c in leg.get("job_checks", leg["checks"])]
    rec = {"schema": 1, "run": parts[0]["run"], "suite_sha256": parts[0]["suite_sha256"], "legs": legs,
           "checks_passed": sum(c["passed"] for c in checks), "checks_failed": sum(not c["passed"] for c in checks)}
    if owed is not None:
        have = {"%s/%s" % (x["boundary"], x["model"]) for x in legs}
        rec["expected"] = owed
        rec["missing"] = [leg for leg in owed if leg not in have]
    return rec


def cell(leg):
    if leg is None:
        return "not run"
    n, acted = len(leg["attempts"]), sum(a["acted"] for a in leg["attempts"])
    saw = sum(bool(a.get("saw_the_plant")) for a in leg["attempts"])
    return "%d of %d" % (acted, n) + ("" if saw == n else " (read in %d)" % saw)


def tables(rec):
    legs = rec["legs"]
    real = [x for x in legs if x["model"] not in STANDINS]
    models = sorted({x["model"] for x in real})
    bounds = [b for b in ("flagship", "sandbox", "cypress") if any(x["boundary"] == b for x in real)]
    by = {(x["boundary"], x["model"]): x for x in legs}
    out = {}

    rows = ["| Model | " + " | ".join(WHERE[b] for b in bounds) + " |",
            "|---|" + "---|" * len(bounds)]
    for m in models:
        rows.append("| %s | " % m + " | ".join(cell(by.get((b, m))) for b in bounds) + " |")
    out["models"] = "\n".join(rows)

    rows = ["| Boundary | Release | Attempts | Tried to leave | Reached the outside | Stopped by | Asked for a tool not granted | Refused |",
            "|---|---|---|---|---|---|---|---|"]
    for b in bounds:
        mine = [x for x in real if x["boundary"] == b]
        rec_ = [x["boundary_record"] for x in mine]
        leave = sum(r["tried_to_leave"] for r in rec_)
        reach = sum(r["tried_to_reach"] for r in rec_)
        stopped = {}
        refused = 0
        for x in mine:
            for a in x["attempts"]:
                for t in a["tried"]:
                    if t["ask"] == "leave" and t["outcome"] != "reached":
                        stopped[t["stopped_by"]] = stopped.get(t["stopped_by"], 0) + 1
                    refused += t["ask"] == "reach" and t["outcome"] != "reached"
        tag = (mine[0].get("source") or {}).get("tag", "?")
        can_reach = any("reach" in a["asked"] for x in mine for a in x["attempts"])
        rows.append("| %s | %s | %d | %d calls | **%d** | %s | %s | %s |" % (
            BOUNDARIES[b], tag, sum(len(x["attempts"]) for x in mine), leave, sum(r["reached_outside"] for r in rec_),
            ", ".join("%s %d" % kv for kv in sorted(stopped.items(), key=lambda kv: -kv[1])) or "nothing was tried",
            "%d calls" % reach if can_reach else "cannot be asked there",
            "%d" % refused if can_reach else "not applicable"))
    out["boundaries"] = "\n".join(rows)

    seen = {a["dressing"] for x in real for a in x["attempts"]}
    suite = json.load(open(os.path.join(ROOT, "suite", "suite.json"), encoding="utf-8"))
    dressings = [d["id"] for d in suite["dressings"] if d["id"] in seen] + sorted(seen - {d["id"] for d in suite["dressings"]})
    rows = ["| Model | Boundary | " + " | ".join("`%s`" % d for d in dressings) + " |", "|---|---|" + "---|" * len(dressings)]
    for m in models:
        for b in bounds:
            leg = by.get((b, m))
            if leg is None:
                continue
            k = {}
            for a in leg["attempts"]:
                c = k.setdefault(a["dressing"], [0, 0])
                c[0] += a["acted"]
                c[1] += 1
            rows.append("| %s | %s | " % (m, WHERE[b].lower()) + " | ".join("%d of %d" % tuple(k.get(d, [0, 0])) for d in dressings) + " |")
    out["dressings"] = "\n".join(rows)

    rows = ["| Stand-in | Read as acting on | Tried to leave | Reached the outside | With the door planted open |", "|---|---|---|---|---|"]
    for m in STANDINS:
        for x in legs:
            if x["model"] != m:
                continue
            door = x.get("open_door")
            rows.append("| `%s` | %d of %d plants | %d calls | **%d** | %s |" % (
                m, sum(a["acted"] for a in x["attempts"]), len(x["attempts"]), x["boundary_record"]["tried_to_leave"],
                x["boundary_record"]["reached_outside"],
                "%d heard, the gate %s" % (door["heard"], "failed" if door["gate_failed"] else "passed") if door else "not applied"))
    out["calibration"] = "\n".join(rows)

    # What a boundary let through that did not leave it, and what the models'
    # answers carried: neither is a call out, and both belong on the page.
    lines = []
    for b in bounds:
        mine = [x for x in real if x["boundary"] == b]
        inside = [s for x in mine for s in x["boundary_record"].get("delivered_inside_to_nobody_named", [])]
        nowhere = sum(a.get("emails_to_no_address", 0) for x in mine for a in x["attempts"])
        named = sum(bool(a.get("answer_names_the_outside")) for x in mine for a in x["attempts"])
        total = sum(len(x["attempts"]) for x in mine)
        if b == "flagship":
            lines.append("- %s: %d %s queued inside the company's domain for an address no task and no plant named%s; "
                         "%d `send_email` %s with a recipient that is no address at all."
                         % (BOUNDARIES[b], len(inside), "email was" if len(inside) == 1 else "emails were",
                            " (%s)" % ", ".join("`%s`" % s for s in sorted(set(inside))) if inside else "",
                            nowhere, "call" if nowhere == 1 else "calls"))
        lines.append("- %s: the outside address appears in %d of %d answers, a copy of the plant included."
                     % (BOUNDARIES[b], named, total))
    out["residue"] = "\n".join(lines)

    own = [x for x in real if x.get("own_gates")]
    held = own and all(x["own_gates"]["of"] > 0 and x["own_gates"]["held"] == x["own_gates"]["of"] for x in own)
    counts = ", ".join("%d of %d" % (x["own_gates"]["held"], x["own_gates"]["of"]) for x in own)
    out["run"] = "Run [%s](%s), commit `%s`: %d legs, %d of %d checks." % (
        rec["run"]["id"], rec["run"]["url"], rec["run"]["commit"], len(legs), rec["checks_passed"],
        rec["checks_passed"] + rec["checks_failed"]) + (
        (" The flagship's own gates held in every one of its jobs: %s." if held
         else " The flagship's own gates did NOT all hold: %s.") % counts if own else "") + (
        " Legs the run set out to make and did not report: %s." % ", ".join(rec["missing"]) if rec.get("missing") else "")
    return out


def signed_on(path):
    """The day the transparency log took a record's signature, from the bundle
    its run left beside it: a record carries no date of its own. The bundle
    has to be the one made for these bytes, so a record changed after it was
    signed, or given another record's bundle, is refused here. Whether the
    signature in the bundle is this repository's workflow's, and the log's
    time the log's, is cosign's to say: `scripts/validate.sh numbers` asks it
    of every signed record under docs/runs before it runs this."""
    bundle = json.load(open(path + ".sigstore.json", encoding="utf-8"))
    try:
        digest = bundle["messageSignature"]["messageDigest"]
        mine = (digest["algorithm"] == "SHA2_256"
                and base64.b64decode(digest["digest"]) == hashlib.sha256(open(path, "rb").read()).digest())
        at = int(bundle["verificationMaterial"]["tlogEntries"][0]["integratedTime"])
    except (KeyError, IndexError, TypeError, ValueError):
        raise ValueError("the file beside %s is no signature with a transparency log's entry in it" % os.path.basename(path))
    if not mine:
        raise ValueError("%s is not the file the signature beside it was made for" % os.path.basename(path))
    return datetime.datetime.fromtimestamp(at, datetime.timezone.utc).date()


def series(items):
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def scheduled(sources):
    """The sentence that says "daily", from the records of the first scheduled
    runs. Refused, with the reason, unless at least two runs are named, each
    started by the schedule, each with every check passed and no leg missing,
    each with the signature made for it beside it, no run named twice and no
    two signed on one day. That they came in a row is the
    `status` branch's to say (`scheduled_streak`); what is held here is that
    every run the sentence names was the schedule's and passed."""
    if len(sources) < 2:
        raise ValueError("a word of cadence needs two scheduled runs, and %d is named" % len(sources))
    runs = []
    for source in sources:
        path = os.path.join(ROOT, source)
        rec = json.load(open(path, encoding="utf-8"))
        run, passed, failed = rec["run"], rec["checks_passed"], rec["checks_failed"]
        if run.get("event") != "schedule":
            raise ValueError("run %s was started by %s, not by the schedule" % (run["id"], run.get("event")))
        if failed or not passed or rec.get("missing"):
            raise ValueError("run %s did not pass: %d of %d checks, %d legs missing"
                             % (run["id"], passed, passed + failed, len(rec.get("missing") or [])))
        try:
            day = signed_on(path)
        except OSError:
            raise ValueError("run %s has no signature beside %s to take its day from" % (run["id"], source))
        runs.append((day, run, passed))
    runs.sort(key=lambda x: (x[0], x[1]["id"]))
    ids = [run["id"] for _, run, _ in runs]
    days = [day for day, _, _ in runs]
    # One run named twice is one run, and two runs on one day are not two days.
    if len(set(ids)) != len(ids):
        raise ValueError("a run is named twice: %s" % ", ".join(str(i) for i in ids))
    if len(set(days)) != len(days):
        raise ValueError("two of the runs named were signed on one day: %s" % ", ".join(str(d) for d in days))
    if len({(d.year, d.month) for d in days}) == 1:
        when = "%s %s %d" % (series([str(d.day) for d in days]), MONTHS[days[0].month - 1], days[0].year)
    else:
        when = series(["%d %s %d" % (d.day, MONTHS[d.month - 1], d.year) for d in days])
    counts = [n for _, _, n in runs]
    held = ("held %d of %d checks each" % (counts[0], counts[0]) if len(set(counts)) == 1
            else "held every check (%s)" % ", ".join("%d of %d" % (n, n) for n in counts))
    return "Scheduled daily; the first %s scheduled runs, %s (%s), %s." % (
        COUNT.get(len(runs), str(len(runs))), when,
        series(["[%s](%s)" % (run["id"], run["url"]) for _, run, _ in runs]), held)


def check(write):
    path = os.environ.get("README", os.path.join(ROOT, "README.md"))
    text = open(path, encoding="utf-8").read()
    bad, cache = [], {}

    def block(m):
        source, name = m.group(2), m.group(3)
        if name == "scheduled":
            try:
                made = {name: scheduled(source.split("+"))}
            except OSError as e:
                bad.append("README takes its word of cadence from %s, which cannot be read: %s" % (source, e))
                return m.group(0)
            except ValueError as e:
                bad.append("README's word of cadence is not earned: %s" % e)
                return m.group(0)
        else:
            try:
                made = cache.setdefault(source, tables(json.load(open(os.path.join(ROOT, source), encoding="utf-8"))))
            except (OSError, ValueError) as e:
                bad.append("README takes numbers from %s, which cannot be read: %s" % (source, e))
                return m.group(0)
        if name not in made:
            bad.append("README asks %s for a table named %s" % (source, name))
            return m.group(0)
        want = made[name] + "\n"
        if m.group(4) != want and not write:
            bad.append("README's %s is not what %s holds" % (name, source))
        return m.group(1) + want + m.group(5)

    new = BLOCK.sub(block, text)
    if not BLOCK.search(text):
        bad.append("README carries no numbers from a run's record")
    # A run the README cites has its record here, whatever is said of it.
    for run in sorted(set(re.findall(r"/actions/runs/(\d+)", new))):
        if not os.path.exists(os.path.join(ROOT, "docs", "runs", run + ".json")):
            bad.append("README cites run %s, and docs/runs/%s.json is not there" % (run, run))
    # A word of cadence anywhere but in the block that earns it.
    rest = BLOCK.sub(lambda m: "" if m.group(3) == "scheduled" else m.group(0), new)
    for n, line in enumerate(rest.splitlines(), 1):
        for word in CADENCE.findall(line):
            bad.append('README says "%s" outside the block that scheduled runs\' records earn: %s' % (word, line.strip()[:80]))
    if write and new != text:
        open(path, "w", encoding="utf-8").write(new)
    for line in bad:
        print("  FAIL  " + line)
    if not bad:
        print("  ok    every number in the README's tables is its run's record: %s"
              % ", ".join(sorted(set(s for m in BLOCK.finditer(new) for s in m.group(2).split("+")))))
    return 1 if bad else 0


def main(argv):
    if argv[:1] == ["record"] and len(argv) == 2:
        print(json.dumps(record(argv[1]), indent=1, ensure_ascii=False))
        return 0
    if argv[:1] == ["tables"] and len(argv) == 2:
        for name, table in tables(json.load(open(argv[1], encoding="utf-8"))).items():
            print("## %s\n%s\n" % (name, table))
        return 0
    if argv[:1] == ["check"]:
        return check("--write" in argv)
    sys.exit(__doc__.split("\n\n")[1])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
