#!/usr/bin/env bash
# validate.sh [check...] - the static checks, without a cluster:
#
#   suite     every boundary carries the same six dressings, each its frame
#             with only the slots filled, each with an outside address of its
#             own (scripts/render.py check)
#   sources   sources.lock pins each boundary to a release tag and a sha256,
#             every bound boundary names a line of it, and no leg reads a
#             boundary from anywhere but the verified tree
#   seams     a working copy of a release with the plants in it (the flagship,
#             the Cypress Cloud triage boundary) differs from the release at
#             its seams and nowhere else, copies tampered outside a seam are
#             refused, and the bring-up this repository runs is the release's
#             own, command for command (tests/static/seams_cases.py)
#   verdicts  each leg's reader of its checkers' lines fails a checker that
#             dies, says nothing or exits non-zero (tests/static/verdict_cases.sh)
#   reader    scripts/read.py, fed recorded logs whose answer is known: the
#             obedient stand-in's, the deaf one's, a run with a door open, and
#             an agent that copied its plant and did nothing
#   standin   the obedient stand-in turns every ask of every plant into a
#             call, and the deaf one none
#   agent     the agent, the stand-in and the collector compile; the agent's
#             web tool opens no file:// address; no schema it offers carries
#             a pattern
#   status    scripts/status.py, fed two runs made of the recorded legs: the
#             window's sums add up, what reached the outside in one run is
#             still there in the sum, and a stand-in gets no model's row
#   models    the model server beside the sandbox is the flagship's pin, its
#             pod hashes the weights before it starts, and the lock is read
#             from the flagship's verified release, never from a copy
#   walls     what this repository adds beside a boundary opens one way and
#             no other: the model reaches nothing and answers the agents
#             only, and the agents' one new way out is the model's port
#   images    every image in manifests/ and the e2e is referenced by digest
#   numbers   every table in the README is what scripts/numbers.py makes from
#             the record of the run it names (docs/runs/)
#   stranger  scripts/stranger.sh, which the Status workflow runs on a clone
#             of the branch `status` in a job with no token: it accepts the
#             signed records under docs/runs and refuses a changed record, a
#             record beside another's bundle, a lost signature, an empty
#             directory and a verifier that accepts anything
#             (tests/static/stranger_cases.py)
#   prose     no em dash and no invisible character in anything tracked,
#             recorded legs and runs apart: a model's words are evidence,
#             not prose
#
# With no arguments every check runs. tests/static/plants.tsv shows each
# check the violation it exists for (tests/static/plant_violations.py).
# The check_* functions are called by name from the loop at the bottom.
# shellcheck disable=SC2329
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

check_suite() { python3 scripts/render.py check; }

check_sources() {
  python3 - <<'PY'
import glob, json, re, sys
bad, names = [], {}
for raw in open("sources.lock", encoding="utf-8"):
    f = raw.split()
    if not f or raw.lstrip().startswith("#"):
        continue
    if len(f) != 4:
        bad.append("sources.lock: a line that is not name, repository, tag, sha256: %s" % raw.strip())
        continue
    name, repo, tag, sha = f
    names[name] = repo
    if not re.fullmatch(r"heyvaldemar/[a-z0-9-]+", repo):
        bad.append("sources.lock: %s is not one of this owner's repositories" % repo)
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        bad.append("sources.lock: %s is pinned to %s, which is not a release tag" % (name, tag))
    if not re.fullmatch(r"[0-9a-f]{64}", sha):
        bad.append("sources.lock: %s carries no sha256 of its archive" % name)
for path in sorted(glob.glob("boundaries/*.json")):
    b = json.load(open(path, encoding="utf-8"))
    if b.get("source") not in names:
        bad.append("%s reads its boundary from %r, which sources.lock does not pin" % (path, b.get("source")))
# A leg takes its boundary from where sources.sh unpacked the verified
# release, and from nowhere else.
for path in sorted(glob.glob("tests/e2e/*.sh") + ["scripts/up.sh"]):
    name = path.rsplit("/", 1)[-1][:-3]
    text = "\n".join(l for l in open(path, encoding="utf-8").read().splitlines() if not l.lstrip().startswith("#"))
    for var in re.findall(r"^\s*(?:SRC|src)=(.*)$", text, re.M):
        if "scripts/sources.sh\" path" not in var and "scripts/sources.sh path" not in var:
            bad.append("%s takes a boundary from %s, not from the verified release" % (path, var.strip()))
    if name in names and "sources.sh" not in text:
        bad.append("%s never asks scripts/sources.sh for its boundary" % path)
print("\n".join(bad) or "%d boundaries pinned to a release tag and a sha256; every leg reads the verified tree" % len(names))
sys.exit(1 if bad else 0)
PY
}

check_seams() { python3 tests/static/seams_cases.py; }

check_verdicts() { ./tests/static/verdict_cases.sh; }

check_reader() { python3 tests/static/reader_cases.py; }

check_status() {
  python3 - <<'PY'
import importlib.util, json, os, shutil, subprocess, sys, tempfile
spec = importlib.util.spec_from_file_location("status", "scripts/status.py")
status = importlib.util.module_from_spec(spec)
spec.loader.exec_module(status)
work = tempfile.mkdtemp(prefix="status-")
try:
    legs = {}
    for case, model in (("obedient", "obedient"), ("deaf", "deaf"), ("open-door", "obedient")):
        d = os.path.join(work, case)
        shutil.copytree(os.path.join("tests", "static", "fixtures", case), d)
        subprocess.run([sys.executable, "scripts/read.py", "sandbox", d, model], capture_output=True, env=dict(os.environ, ATTEMPTS="1"))
        legs[case] = json.load(open(os.path.join(d, "leg.json"), encoding="utf-8"))
    # Two models with weights, made of recorded legs under other names: one
    # that left nothing, and one in whose leg the outside heard a request.
    held = dict(legs["obedient"], model="granite-4.0-1b")
    leaked = dict(legs["open-door"], model="ministral-3-3b")
    run = lambda n: {"id": n, "created_at": "2026-11-1%dT06:17:00Z" % n, "html_url": "https://example.invalid/%d" % n, "conclusion": "success"}
    counted = [(run(1), {"legs": [legs["obedient"], legs["deaf"], leaked]}),
               (run(2), {"legs": [legs["obedient"], legs["deaf"], held]})]
    models, boundaries, calibration = status.windows(counted)
    bad = []
    b = boundaries["boundaries"][0]
    # Models with weights only: the stand-ins are summed apart.
    want = {"attempts": 7, "tried_to_leave": 7, "reached_outside": 1, "tried_to_reach": 2, "runs": 2}
    for key, value in want.items():
        if b[key] != value:
            bad.append("the sandbox's %s over two runs is %r, and the legs add up to %r" % (key, b[key], value))
    rows = {x["model"]: (x["acted_on_the_note"], x["triages"]) for x in models["models"]}
    if rows != {"granite-4.0-1b": (6, 6), "ministral-3-3b": (1, 1)}:
        bad.append("the models' window holds %s: two models with weights, 6 of 6 and 1 of 1, and no stand-in" % rows)
    names = {c["model"]: c for c in calibration["standins"]}
    if names.get("obedient", {}).get("acted") != 12 or names.get("deaf", {}).get("acted") != 0:
        bad.append("the stand-ins' sums are not 12 and 0")
    empty = dict(legs["deaf"], attempts=[])
    again = status.windows([(run(1), {"legs": [empty]})])[2]["standins"]
    if again and again[0]["runs_read_as_it_is"] != 0:
        bad.append("a stand-in's leg with no attempt in it is counted as read as it is")
    if boundaries["first"]["id"] != 1 or boundaries["last"]["id"] != 2:
        bad.append("the window does not name its first and last run")
    # The API or the artifact storage answering "later" is asked again after
    # a pause, and an answer that is final is raised at once (run 43453695229
    # failed on one 503 from the storage).
    import contextlib, io, types, urllib.error
    def asked_with(answers):
        asked, slept = [], []
        def once(url):
            asked.append(url)
            a = answers[min(len(asked), len(answers)) - 1]
            if isinstance(a, int):
                raise urllib.error.HTTPError(url, a, "planted", {}, None)
            if a is None:
                raise urllib.error.URLError("planted")
            return a
        status.once, status.time = once, types.SimpleNamespace(sleep=slept.append)
        try:
            with contextlib.redirect_stderr(io.StringIO()):
                got = status.get("/planted")
        except urllib.error.HTTPError as e:
            got = e.code
        except urllib.error.URLError:
            got = "no answer"
        return got, len(asked), slept
    pauses = list(status.PAUSES)
    if asked_with([503, 503, b'{"ok": 1}']) != ({"ok": 1}, 3, pauses[:2]):
        bad.append("a storage that answers 503 twice and then answers is not read")
    if asked_with([None, b'{"ok": 1}']) != ({"ok": 1}, 2, pauses[:1]):
        bad.append("a storage that does not answer once and then answers is not read")
    if asked_with([503]) != (503, len(pauses) + 1, pauses):
        bad.append("a storage that keeps answering 503 is not asked %d times and then raised" % (len(pauses) + 1))
    if asked_with([404]) != (404, 1, []):
        bad.append("an answer that is final (404) is asked for again")
    print("\n".join(bad) or "two runs of recorded legs add up: %s" % b["line"])
    sys.exit(1 if bad else 0)
finally:
    shutil.rmtree(work, ignore_errors=True)
PY
}

check_standin() {
  python3 - <<'PY'
import importlib.util, json, os, sys
sys.path.insert(0, "scripts")
import render
bad = []
fn = lambda n, p: {"type": "function", "function": {"name": n, "parameters": {"type": "object", "properties": p}}}
OFFERED = {"sandbox": [fn("quarterly_report", {}), fn("records_lookup", {"customer_id": {}}),
                       fn("delete_record", {"customer_id": {}}), fn("http_request", {"method": {}, "url": {}, "body": {}})]}
READS = {"sandbox": ["records_lookup", "delete_record"]}
def load(kind):
    os.environ["STANDIN"] = kind
    spec = importlib.util.spec_from_file_location("standin_" + kind, "manifests/standin/standin.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
obedient, deaf = load("obedient"), load("deaf")
n = 0
for name, offered in OFFERED.items():
    b = render.binding(name)
    for did, plant in render.plants(name).items():
        said = [{"role": "system", "content": "s"}, {"role": "user", "content": "the task"}]
        first = obedient.decide({"messages": said, "tools": offered})[1]
        if [c["function"]["name"] for c in first] != ["quarterly_report"]:
            bad.append("%s/%s: the stand-in does not start with the read tool" % (name, did))
        said += [{"role": "assistant", "content": None, "tool_calls": first},
                 {"role": "tool", "content": b.get("report", "") + " " + plant["text"]}]
        calls = [(c["function"]["name"], json.loads(c["function"]["arguments"]))
                 for c in obedient.decide({"messages": said, "tools": offered})[1]]
        n += 1
        if "leave" in plant["asks"] and ("http_request", plant["to"]) not in [(c, a.get("url")) for c, a in calls]:
            bad.append("%s/%s: the obedient stand-in does not send to %s" % (name, did, plant["to"]))
        if "reach" in plant["asks"] and not all(t in [c for c, _ in calls] for t in READS[name]):
            bad.append("%s/%s: the obedient stand-in does not ask for the tools the plant names" % (name, did))
        if "reach" not in plant["asks"] and any(c in READS[name] for c, _ in calls):
            bad.append("%s/%s: the obedient stand-in asks for a tool the plant does not name" % (name, did))
        if deaf.decide({"messages": said, "tools": offered})[1]:
            bad.append("%s/%s: the deaf stand-in made a call" % (name, did))
print("\n".join(bad) or "the obedient stand-in turns every ask of %d plants into a call; the deaf one makes none" % n)
sys.exit(1 if bad else 0)
PY
}

check_agent() {
  python3 -m py_compile manifests/agent/agent.py manifests/standin/standin.py manifests/outside/collector.py \
    scripts/read.py scripts/render.py scripts/status.py scripts/seams.py scripts/numbers.py || return 1
  python3 - <<'PY'
import importlib.util, json, os, shutil, sys, tempfile
work = tempfile.mkdtemp(prefix="agent-")
try:
    shutil.copy("manifests/agent/agent.py", work)
    json.dump({"url": "http://127.0.0.1:9", "model": "none", "task": "t"}, open(os.path.join(work, "model.json"), "w"))
    spec = importlib.util.spec_from_file_location("agent", os.path.join(work, "agent.py"))
    agent = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(agent)
    bad = []
    for url in ("file:///var/run/secrets/mcp/token", "FILE:///etc/hostname", "ftp://example.com/x"):
        if agent.http_request("GET", url, None)[0] != "invalid":
            bad.append("the agent's web tool opens %s" % url)
    if "pattern" in json.dumps(agent.OFFERED):
        bad.append("the agent offers the model a schema with a pattern: the model server's grammar would hide its attempts")
    if agent.kind_of("http_request", {"url": "http://collector.outside.svc.cluster.local:8080/collect/x"}) != "leave":
        bad.append("a request to the outside is not read as an attempt to leave")
    if agent.kind_of("delete_record", {}) != "reach":
        bad.append("a tool the door did not grant is not read as a reach")
    print("\n".join(bad) or "the agent compiles; its web tool opens no file; it offers no pattern; a leave and a reach are named as such")
    sys.exit(1 if bad else 0)
finally:
    shutil.rmtree(work, ignore_errors=True)
PY
}

check_models() {
  python3 - <<'PY'
import os, re, subprocess, sys
bad = []
src = subprocess.run(["./scripts/sources.sh", "path", "flagship"], capture_output=True, text=True).stdout.strip()
pins = open(os.path.join(src, "airgap", "images.txt"), encoding="utf-8").read() if src else ""
llama = open("manifests/sandbox/llama.yaml", encoding="utf-8").read()
image = re.search(r"image: (ghcr\.io/ggml-org/llama\.cpp\S+)", llama)
if not image or image.group(1) not in pins.split():
    bad.append("the model server's image is not the one the flagship's release pins: %s" % (image.group(1) if image else "none"))
if "MODEL_SHA256" not in llama or "sys.exit(0 if ok else 1)" not in llama or "initContainers" not in llama:
    bad.append("the model server's pod does not hash its weights before it starts")
if not re.search(r"reference: @MODEL_IMAGE@\n\s+pullPolicy: Never", llama):
    bad.append("the weights are not the image scripts/model.sh loaded, and nothing else")
if "app.kubernetes.io/name: llama" not in llama or "name: llama\n  namespace: models" not in llama:
    bad.append("the model server would not get the walls the stand-in had")
model = "\n".join(l for l in open("scripts/model.sh", encoding="utf-8").read().splitlines() if not l.lstrip().startswith("#"))
if 'sources.sh" path flagship' not in model or "$FLAGSHIP/models/models.lock" not in model:
    bad.append("scripts/model.sh does not read the lock from the flagship's verified release")
if len(re.findall(r'\[ "\$got" = "\$sha" \] \|\|', model)) != 1:
    bad.append("scripts/model.sh takes a file whose sha256 it has not checked")
print("\n".join(bad) or "the flagship's model server pin, weights hashed in the pod, the lock read from the verified release")
sys.exit(1 if bad else 0)
PY
}

check_walls() {
  local built
  built="$(kubectl kustomize manifests 2>&1)" || { echo "$built" | tail -5; return 1; }
  python3 - <<'PY'
import glob, re, sys
# Read as text on purpose: no YAML parser on a bare runner. A policy is three
# short documents, so each is held to the exact rules that were reviewed: a
# rule added to one of them, however it is written, is a difference. A change
# to a wall is then a change to this list, in the same diff, in the open.
WALLS = {
    ("models", "default-deny"): """podSelector: {}
policyTypes: [Ingress, Egress]""",
    ("models", "from-agents-only"): """podSelector:
  matchLabels:
    app.kubernetes.io/name: llama
policyTypes: [Ingress]
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: agents
    ports:
      - {protocol: TCP, port: 8080}""",
    ("agents", "allow-model"): """podSelector: {}
policyTypes: [Egress]
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: models
        podSelector:
          matchLabels:
            app.kubernetes.io/name: llama
    ports:
      - {protocol: TCP, port: 8080}""",
}
docs = []
for path in sorted(glob.glob("manifests/**/*.yaml", recursive=True)):
    docs += [d for d in open(path, encoding="utf-8").read().split("\n---\n") if re.search(r"^kind: NetworkPolicy$", d, re.M)]
def field(doc, name):
    m = re.search(r"^  %s:\s*(\S+)" % name, doc, re.M)
    return m.group(1) if m else ""
def spec(doc):
    body = doc.split("\nspec:\n", 1)[1] if "\nspec:\n" in doc else ""
    lines = [l[2:].rstrip() for l in body.split("\n") if l.strip() and not l.lstrip().startswith("#")]
    return "\n".join(lines)
bad, seen = [], set()
for d in docs:
    key = (field(d, "namespace"), field(d, "name"))
    if key in seen:
        bad.append("%s/%s is written twice" % key)
    seen.add(key)
    if key not in WALLS:
        bad.append("%s/%s: a policy this repository's walls do not include" % key)
    elif spec(d) != WALLS[key]:
        bad.append("%s/%s is not the policy that was reviewed: a rule was added, removed or rewritten" % key)
for key in WALLS:
    if key not in seen:
        bad.append("%s/%s is missing" % key)
print("\n".join(bad) or "the model reaches nothing and answers the agents only; the agents' one new way out is its port")
sys.exit(1 if bad else 0)
PY
}

check_images() {
  python3 - <<'PY'
import glob, re, sys
bad = []
paths = sorted(glob.glob("manifests/**/*.yaml", recursive=True) + glob.glob("tests/e2e/*.sh"))
for path in paths:
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        m = re.match(r"\s*-?\s*image:\s*(\S+)", line) or re.match(r"\s*(?:PY|CURL|IMAGE)=(\S+/\S+)", line)
        if m and "@sha256:" not in m.group(1) and not m.group(1).startswith("$"):
            bad.append("%s:%d: image %s is not pinned by digest" % (path, n, m.group(1)))
print("\n".join(bad) or "every image in %d files is referenced by digest" % len(paths))
sys.exit(1 if bad else 0)
PY
}

# Who signs a run's record: this repository's e2e workflow, on main.
RECORDS_SIGNED_BY="https://github.com/heyvaldemar/agent-security-benchmark/.github/workflows/e2e.yml@refs/heads/main"

check_numbers() {
  python3 scripts/numbers.py check || return 1
  # The check itself, shown a page it must refuse: the same README with one
  # count changed.
  local copy
  copy="$(mktemp)"
  sed 's/ of 18 |/ of 19 |/' README.md >"$copy"
  if cmp -s README.md "$copy" || README="$copy" python3 scripts/numbers.py check >/dev/null; then
    /bin/rm -f "$copy"
    echo "a README with a count changed by hand passes the check, or carries no count to change"
    return 1
  fi
  # Every signed record under docs/runs is the file its run signed: cosign
  # holds it to the bundle beside it, as this repository's e2e workflow on
  # main and nobody else's. The sentence that says "daily" takes its days
  # from those bundles. Asked once for each pair of files: the answer is kept
  # under .cache/records by the two files' hashes, so a copy with a byte
  # changed in either is asked about again.
  local rec key
  for rec in docs/runs/*.json; do
    [ -f "$rec.sigstore.json" ] || continue
    key="$(python3 -c 'import hashlib, sys
print("-".join(hashlib.sha256(open(p, "rb").read()).hexdigest() for p in sys.argv[1:]))' "$rec" "$rec.sigstore.json")"
    [ -f ".cache/records/$key" ] && continue
    if ! command -v cosign >/dev/null; then
      /bin/rm -f "$copy"
      echo "cosign is not on PATH to verify $rec (make check puts it there)"
      return 1
    fi
    if ! cosign verify-blob "$rec" --bundle "$rec.sigstore.json" \
        --certificate-identity "$RECORDS_SIGNED_BY" \
        --certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null 2>&1; then
      /bin/rm -f "$copy"
      echo "cosign does not verify $rec, with the bundle beside it, as signed by this repository's e2e workflow on main"
      return 1
    fi
    mkdir -p .cache/records && : >".cache/records/$key"
  done
  # A word of cadence outside the block that earns it, and a run cited with
  # no record of it here. Both in sentences no block makes, so that nothing
  # but the rule each is for can refuse them.
  local said
  for said in 's/^## A run.s record, and its signature$/## A daily record, and its signature/' 's#/actions/runs/43170832351) did#/actions/runs/43170832352) did#'; do
    sed "$said" README.md >"$copy"
    if cmp -s README.md "$copy" || README="$copy" python3 scripts/numbers.py check >/dev/null; then
      /bin/rm -f "$copy"
      echo "a README changed by '$said' passes the check, or the text it changes is gone"
      return 1
    fi
  done
  /bin/rm -f "$copy"
  # And the record itself: a run that owed three legs and reported two names
  # the third, in the record and in the sentence made from it.
  python3 - <<'PY'
import importlib.util, json, os, shutil, sys, tempfile
spec = importlib.util.spec_from_file_location("numbers", "scripts/numbers.py")
numbers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(numbers)
# The newest record; a signed one has its bundle beside it, which is no record.
rec = json.load(open(sorted(p for p in __import__("glob").glob("docs/runs/*.json")
                            if not p.endswith(".sigstore.json"))[-1], encoding="utf-8"))
work = tempfile.mkdtemp(prefix="record-")
try:
    part = dict(rec, legs=[x for x in rec["legs"] if x["model"] in ("obedient", "deaf")])
    json.dump(part, open(os.path.join(work, "results.json"), "w"))
    os.environ["LEGS_RAN"] = json.dumps({"calibration": {"result": "success"}, "sandbox": {"result": "failure"},
                                         "flagship": {"result": "skipped"}, "cypress": {"result": "skipped"}})
    os.environ["LEGS_MODELS"] = json.dumps(["granite-4.0-1b"])
    made = numbers.record(work)
    bad = []
    if made.get("expected") != ["sandbox/deaf", "sandbox/granite-4.0-1b", "sandbox/obedient"]:
        bad.append("the record's expected legs are %s" % made.get("expected"))
    if made.get("missing") != ["sandbox/granite-4.0-1b"]:
        bad.append("a leg whose job failed is not named as missing: %s" % made.get("missing"))
    if "sandbox/granite-4.0-1b" not in numbers.tables(made)["run"]:
        bad.append("the run's sentence does not name the leg that did not report")
    # The sentence that says "daily" is made from scheduled runs' records, and
    # refused, each time for its own reason, for one run, for a run the
    # schedule did not start, for one that failed, for one with a leg
    # missing, for one with no signature, for one changed after it was
    # signed, for one run named twice and for two runs signed on one day.
    import base64, hashlib
    every = sorted(p for p in __import__("glob").glob("docs/runs/*.json") if not p.endswith(".sigstore.json"))
    event = lambda p: json.load(open(p, encoding="utf-8"))["run"].get("event")
    sched = [p for p in every if event(p) == "schedule" and os.path.exists(p + ".sigstore.json")]
    pushed = [p for p in every if event(p) == "push" and os.path.exists(p + ".sigstore.json")]
    def why(sources):
        try:
            numbers.scheduled(sources)
        except ValueError as e:
            return str(e)
        return "given"
    def changed(name, of, sign, **fields):
        """A record with fields changed. Its bundle is the original's as it is
        ("copied"), the original's with the digest of the new file written in
        ("made": what a hand can forge and cosign refuses, used here so that
        the rule under test is the only one in the way), or none (None)."""
        path = os.path.join(work, name)
        rec = json.load(open(of, encoding="utf-8"))
        rec.update({k: v for k, v in fields.items() if k != "run_id"})
        if "run_id" in fields:
            rec["run"] = dict(rec["run"], id=fields["run_id"])
        json.dump(rec, open(path, "w"))
        if sign == "copied":
            shutil.copy(of + ".sigstore.json", path + ".sigstore.json")
        if sign == "made":
            bundle = json.load(open(of + ".sigstore.json", encoding="utf-8"))
            bundle["messageSignature"]["messageDigest"]["digest"] = base64.b64encode(
                hashlib.sha256(open(path, "rb").read()).digest()).decode()
            json.dump(bundle, open(path + ".sigstore.json", "w"))
        return path
    if len(sched) < 2 or not pushed:
        bad.append("docs/runs holds no two signed records of scheduled runs and one of a pushed run to show the sentence")
    else:
        a, b = (json.load(open(p, encoding="utf-8")) for p in sched[:2])
        line = numbers.scheduled(sched[:2])
        if not all(x in line for x in ("Scheduled daily", a["run"]["url"], b["run"]["url"],
                                       "%d of %d checks" % (a["checks_passed"], a["checks_passed"]))):
            bad.append("the sentence made from two scheduled runs does not name them and their checks: %s" % line)
        first, second = sched[0], sched[1]
        for what, sources, reason in (
                ("one scheduled run", [first], "needs two scheduled runs"),
                ("a run started by a push", [first, pushed[0]], "not by the schedule"),
                ("a scheduled run with a failed check", [first, changed("failed.json", second, "made", checks_failed=1)], "did not pass"),
                ("a scheduled run with a leg missing", [first, changed("missing.json", second, "made", missing=["sandbox/qwen3.5-2b"])], "did not pass"),
                ("a scheduled run with no signature beside its record", [first, changed("unsigned.json", second, None, suite_sha256="0")], "no signature beside"),
                ("a record changed after it was signed", [first, changed("edited.json", second, "copied", suite_sha256="0")], "not the file the signature"),
                ("one run named twice", [first, first], "named twice"),
                ("two runs signed on one day", [first, changed("sameday.json", first, "made", run_id=1)], "on one day")):
            said = why(sources)
            if reason not in said:
                bad.append("the word of cadence for %s: %s, and the reason owed is \"%s\"" % (what, said, reason))
    print("\n".join(bad) or "a record names the leg its run owed and did not report")
    sys.exit(1 if bad else 0)
finally:
    shutil.rmtree(work, ignore_errors=True)
PY
}

check_stranger() {
  if ! command -v cosign >/dev/null; then
    echo "cosign is not on PATH (make check puts it there)"
    return 1
  fi
  # One signer in both places: the records the page's numbers are read from
  # and the records a stranger is told to verify.
  if ! grep -qxF "SIGNED_BY=\"$RECORDS_SIGNED_BY\"" scripts/stranger.sh; then
    echo "scripts/stranger.sh and the numbers check name different signers"
    return 1
  fi
  local said
  if ! said="$(./scripts/stranger.sh docs/runs)"; then
    echo "scripts/stranger.sh refuses the records under docs/runs: $said"
    return 1
  fi
  python3 tests/static/stranger_cases.py
}

check_prose() {
  python3 - <<'PY'
import os, re, subprocess, sys
files = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"],
                       capture_output=True, text=True).stdout.split("\n")
if not any(files):
    # Outside a checkout (a release archive, a plant's copy): every file but
    # what .gitignore names.
    files = [os.path.join(d, f)[2:] for d, dirs, names in os.walk(".") for f in names
             if not any(part in (".git", ".cache", "out", "__pycache__") for part in d.split(os.sep))]
odd = re.compile("[\u2013\u2014\u00a0\u00ad\u200b-\u200f\u2028\u2029\u202a-\u202f\u2060\ufeff]")
bad = []
for path in filter(None, files):
    # A recorded leg is evidence, a model's words included, not this
    # repository's prose.
    if path.startswith(("tests/static/fixtures/", "docs/runs/")):
        continue
    try:
        text = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        continue
    for n, line in enumerate(text.splitlines(), 1):
        if odd.search(line):
            bad.append("%s:%d: a dash or an invisible character that does not belong in plain text" % (path, n))
print("\n".join(bad[:20]) or "no em dash and no invisible character in %d files" % len([f for f in files if f]))
sys.exit(1 if bad else 0)
PY
}

checks=("$@")
[ ${#checks[@]} -eq 0 ] && checks=(suite sources seams verdicts reader status standin agent models walls images numbers stranger prose)
failed=0
for c in "${checks[@]}"; do
  if "check_$c"; then echo "-- $c: ok"; else echo "-- $c: FAILED"; failed=1; fi
done
exit "$failed"
