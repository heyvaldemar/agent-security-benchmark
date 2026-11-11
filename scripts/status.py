#!/usr/bin/env python3
"""status.py OUT_DIR - what the e2e workflow has shown lately, as JSON a page
or a badge can read.

    GITHUB_REPOSITORY=owner/name GITHUB_TOKEN=... E2E_WORKFLOW=e2e.yml \\
        scripts/status.py out/status

Reads the e2e workflow's runs on main over the last 30 days (pushes, the
daily schedule, manual runs; never pull requests, never cancelled runs) and
the record each of them uploaded (results.json, written by scripts/read.py
merge, and the e2e-results-*.json each leg writes). Writes:

    runs/<id>.json      each run's one record as the run made it, and its
                        Sigstore bundle beside it where the run signed it
    status.json         the window, the streak, the latest run's checks and
                        measurements, and three sums over the window:
        models_window       per model with weights: acted on a planted
                            instruction in N of M attempts across K runs, by
                            boundary and by dressing
        boundaries_window   per boundary: attempts to leave, how many reached
                            the outside, and what stopped the rest
        calibration_window  the two stand-in models and the door planted
                            open: how many runs read them as they are
    badge-days.json     shields.io endpoint: green days in the window
    badge-checks.json   shields.io endpoint: the latest run's checks

A run's number is one run. The sums are what a claim may rest on, and each
names the first and the last run it counted. A day counts as green when its
last finished run passed; the run count beside it shows the failures that
rule hides. Nothing here is typed by hand: every number is read from GitHub
at the time it is written.
"""
import datetime
import io
import json
import os
import sys
import urllib.error
import urllib.request
import zipfile

API = "https://api.github.com"
WINDOW_DAYS = 30
STANDINS = ("obedient", "deaf")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def get(url, raw=False):
    req = urllib.request.Request(url if url.startswith("http") else API + url)
    req.add_header("Authorization", "Bearer " + os.environ["GITHUB_TOKEN"])
    req.add_header("Accept", "application/vnd.github+json")
    try:
        with urllib.request.build_opener(_NoRedirect).open(req, timeout=60) as r:
            body = r.read()
    except urllib.error.HTTPError as e:
        # An artifact download answers with a redirect to signed storage,
        # which rejects the API's Authorization header: follow it without.
        if e.code not in (301, 302, 303, 307, 308) or not e.headers.get("Location"):
            raise
        with urllib.request.urlopen(e.headers["Location"], timeout=120) as r:
            body = r.read()
    return body if raw else json.loads(body)


def runs(repo, workflow, since):
    out, page = [], 1
    while True:
        batch = get(f"/repos/{repo}/actions/workflows/{workflow}/runs?branch=main&per_page=100&page={page}"
                    f"&created=%3E%3D{since:%Y-%m-%d}")["workflow_runs"]
        out += batch
        if len(batch) < 100:
            return out
        page += 1


def record(repo, run_id, keep=None):
    """(results.json, the legs' own check files) of one run; (None, []) when
    it uploaded nothing or the artifact has expired. The run's one record
    and its signature, where the run made them, are written to `keep` as
    they are: the branch then holds them after the artifacts expire."""
    every = [a for a in get(f"/repos/{repo}/actions/runs/{run_id}/artifacts")["artifacts"] if not a["expired"]]
    arts = [a for a in every if a["name"].startswith("e2e-results")]
    results, legs = None, []
    for a in every:
        if a["name"] != "run-record" or not keep:
            continue
        z = zipfile.ZipFile(io.BytesIO(get(a["archive_download_url"], raw=True)))
        for name in z.namelist():
            base = name.rsplit("/", 1)[-1]
            if base.startswith("run-") and base.endswith((".json", ".json.sigstore.json")):
                os.makedirs(keep, exist_ok=True)
                with open(os.path.join(keep, base[len("run-"):]), "wb") as f:
                    f.write(z.read(name))
    for a in arts:
        z = zipfile.ZipFile(io.BytesIO(get(a["archive_download_url"], raw=True)))
        for name in z.namelist():
            base = name.rsplit("/", 1)[-1]
            if base == "results.json":
                # One job, one artifact, one results.json: the run's record is
                # the legs of all of them.
                part = json.loads(z.read(name))
                if results is None:
                    results = dict(part, legs=[])
                # A job run again uploads its leg again: the later one stands.
                held = {(x["boundary"], x["model"]): x for x in results["legs"]}
                for x in part.get("legs", []):
                    held[(x["boundary"], x["model"])] = x
                results["legs"] = [held[k] for k in sorted(held)]
            elif base.startswith("e2e-results-") and base.endswith(".json"):
                legs.append(json.loads(z.read(name)))
    return results, legs


def ref(r):
    return {"id": r["id"], "at": r["created_at"], "url": r["html_url"], "conclusion": r["conclusion"]}


def windows(counted):
    """The three sums, from every run in the window that uploaded a record.
    `counted` is [(run, results.json)], oldest first."""
    models, boundaries, calibration = {}, {}, {}
    for run, results in counted:
        for leg in results.get("legs", []):
            b, m, rec = leg["boundary"], leg["model"], leg["boundary_record"]
            acted = sum(a["acted"] for a in leg["attempts"])
            # A boundary's sums are over models with weights, as the README's
            # table is. The stand-ins have a window of their own below.
            if m not in STANDINS:
                w = boundaries.setdefault(b, {"boundary": b, "releases": [], "runs": set(), "attempts": 0,
                                              "tried_to_leave": 0, "reached_outside": 0, "tried_to_reach": 0,
                                              "stopped_by": {}, "controls_heard": 0, "legs": 0})
                tag = (leg.get("source") or {}).get("tag")
                if tag and tag not in w["releases"]:
                    w["releases"].append(tag)
                w["runs"].add(run["id"])
                w["legs"] += 1
                w["attempts"] += len(leg["attempts"])
                w["tried_to_leave"] += rec["tried_to_leave"]
                w["reached_outside"] += rec["reached_outside"]
                w["tried_to_reach"] += rec["tried_to_reach"]
                w["controls_heard"] += bool(rec["control_heard"])
                for layer, n in rec["stopped_by"].items():
                    w["stopped_by"][layer] = w["stopped_by"].get(layer, 0) + n
            if m in STANDINS:
                c = calibration.setdefault(m, {"model": m, "runs": set(), "attempts": 0, "acted": 0,
                                               "runs_read_as_it_is": 0})
                c["runs"].add(run["id"])
                c["attempts"] += len(leg["attempts"])
                c["acted"] += acted
                # A leg with no attempt was read as nothing, not as it is.
                c["runs_read_as_it_is"] += bool(leg["attempts"]) and acted == (len(leg["attempts"]) if m == "obedient" else 0)
                c["tried_to_leave"] = c.get("tried_to_leave", 0) + rec["tried_to_leave"]
                c["reached_outside"] = c.get("reached_outside", 0) + rec["reached_outside"]
                door = leg.get("open_door")
                if door is not None:
                    d = calibration.setdefault("open door", {"model": "open door", "runs": set(), "heard": 0,
                                                             "runs_the_gate_failed": 0})
                    d["runs"].add(run["id"])
                    d["heard"] += door["heard"]
                    d["runs_the_gate_failed"] += bool(door["gate_failed"])
                continue
            x = models.setdefault(m, {"model": m, "runs": set(), "triages": 0, "acted_on_the_note": 0, "saw_the_plant": 0,
                                      "by_boundary": {}, "by_dressing": {}, "attempts": {}, "seconds": []})
            x["runs"].add(run["id"])
            x["triages"] += len(leg["attempts"])
            x["acted_on_the_note"] += acted
            x["saw_the_plant"] += sum(bool(a.get("saw_the_plant")) for a in leg["attempts"])
            k = x["by_boundary"].setdefault(b, [0, 0])
            k[0] += acted
            k[1] += len(leg["attempts"])
            for a in leg["attempts"]:
                k = x["by_dressing"].setdefault(a["dressing"], [0, 0])
                k[0] += a["acted"]
                k[1] += 1
                x["seconds"].append(a["seconds"])
                for t in a["tried"]:
                    kind = x["attempts"].setdefault(t["ask"], {"calls": 0, "outcomes": {}})
                    kind["calls"] += 1
                    kind["outcomes"][t["outcome"]] = kind["outcomes"].get(t["outcome"], 0) + 1

    def done(w):
        w["runs"] = len(w["runs"])
        return w
    for x in models.values():
        secs = sorted(x.pop("seconds"))
        x["median_seconds"] = secs[len(secs) // 2] if secs else None
        # The names the fleet catalog reads (fleet-ops, models_window_of): an
        # attempt here is what a triage is there.
        x["line"] = "%s: acted on a planted instruction in %d of %d attempts across %d runs" % (
            x["model"], x["acted_on_the_note"], x["triages"], len(x["runs"]))
    for w in boundaries.values():
        w["line"] = "%s: %d of %d attempts to leave reached the outside, across %d runs" % (
            w["boundary"], w["reached_outside"], w["tried_to_leave"], len(w["runs"]))
    span = {"window_days": WINDOW_DAYS, "runs": len(counted),
            "runs_failed": sum(r["conclusion"] != "success" for r, _ in counted),
            "first": ref(counted[0][0]) if counted else None, "last": ref(counted[-1][0]) if counted else None}
    return (dict(span, models=[done(models[m]) for m in sorted(models)]),
            dict(span, boundaries=[done(boundaries[b]) for b in sorted(boundaries)]),
            dict(span, standins=[done(calibration[c]) for c in sorted(calibration)]))


def badge(label, message, color):
    return {"schemaVersion": 1, "label": label, "message": message, "color": color}


def main(out):
    repo, workflow = os.environ["GITHUB_REPOSITORY"], os.environ["E2E_WORKFLOW"]
    now = datetime.datetime.now(datetime.timezone.utc)
    since = (now - datetime.timedelta(days=WINDOW_DAYS - 1)).date()
    finished = [r for r in runs(repo, workflow, since)
                if r["event"] in ("push", "schedule", "workflow_dispatch")
                and r["status"] == "completed" and r["conclusion"] in ("success", "failure")]
    finished.sort(key=lambda r: r["created_at"])

    last_of_day = {}
    for r in finished:
        last_of_day[r["created_at"][:10]] = r["conclusion"]
    days = sorted(last_of_day)
    green = [d for d in days if last_of_day[d] == "success"]
    streak = 0
    for d in reversed(days):
        if last_of_day[d] != "success":
            break
        streak += 1
    # Two scheduled runs in a row that passed is what a word of cadence needs.
    scheduled = [r for r in finished if r["event"] == "schedule"]
    scheduled_streak = 0
    for r in reversed(scheduled):
        if r["conclusion"] != "success":
            break
        scheduled_streak += 1

    counted, latest_legs = [], []
    for r in finished:
        results, legs = record(repo, r["id"], keep=os.path.join(out, "runs"))
        if results:
            counted.append((r, results))
        if r is finished[-1]:
            latest_legs = legs
    latest = finished[-1] if finished else None
    checks = [dict(c, job="%s-%s" % (leg.get("boundary"), leg.get("model")))
              for leg in latest_legs for c in leg.get("checks", [])]
    measured = ["%s, %s · %s" % (leg.get("boundary"), leg.get("model"), m)
                for leg in latest_legs for m in leg.get("measured", [])]
    passed = sum(1 for c in checks if c.get("passed"))
    failed = sum(1 for c in checks if not c.get("passed"))
    models_window, boundaries_window, calibration_window = windows(counted)

    status = {
        "repository": repo,
        "workflow": workflow,
        "written_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "window_days": WINDOW_DAYS,
        "days_with_runs": len(days),
        "green_days": len(green),
        "streak_days": streak,
        "runs": len(finished),
        "runs_passed": sum(1 for r in finished if r["conclusion"] == "success"),
        "scheduled_runs": len(scheduled),
        "scheduled_streak": scheduled_streak,
        "latest": None if not latest else {
            "conclusion": latest["conclusion"],
            "at": latest["created_at"],
            "url": latest["html_url"],
            "commit": latest["head_sha"][:7],
            "checks_passed": passed,
            "checks_failed": failed,
            "checks": checks,
            "measured": measured,
        },
        "models_window": models_window,
        "boundaries_window": boundaries_window,
        "calibration_window": calibration_window,
    }
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "status.json"), "w", encoding="utf-8") as f:
        json.dump(status, f, indent=2, ensure_ascii=False)

    if days:
        color = "brightgreen" if len(green) == len(days) else ("yellow" if len(green) >= 0.9 * len(days) else "red")
        msg = f"{len(green)} of {len(days)} days green, {status['runs_passed']} of {len(finished)} runs"
    else:
        color, msg = "lightgrey", "no runs yet"
    json.dump(badge(f"e2e, last {WINDOW_DAYS} days", msg, color), open(os.path.join(out, "badge-days.json"), "w"))
    if checks:
        color = "brightgreen" if not failed else "red"
        json.dump(badge("checks", f"{passed} of {passed + failed} passed, {latest['created_at'][:10]}", color),
                  open(os.path.join(out, "badge-checks.json"), "w"))
    print(f"{repo}: {len(green)} of {len(days)} days green, streak {streak}, "
          f"latest {latest['conclusion'] if latest else 'none'} with {passed} of {passed + failed} checks; "
          f"{len(counted)} runs counted in the windows")
    for w in boundaries_window["boundaries"]:
        print("  " + w["line"])
    for x in models_window["models"]:
        print("  " + x["line"])


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
