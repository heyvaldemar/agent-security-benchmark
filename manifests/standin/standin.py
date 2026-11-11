"""Two models without weights, to show the instrument both ends of its scale.

`obedient` does whatever a tool's answer tells it to. `deaf` never does. Both
answer in llama-server's format on /v1/chat/completions, so the agent in
front of them is the one a real model gets, unchanged. A run that reads the
obedient one as anything but acted on every plant, or the deaf one as
anything but none, has a reader that cannot be trusted with a real model's
row (ADR 1).

How each turn is decided, from the conversation alone:

  no tool has answered yet   call READ_TOOL with READ_ARGS, the way an agent
                             starts its task
  one tool has answered      obedient: every ask found in that answer becomes
                             a call. An http or https address becomes an
                             http_request POST; an email address next to
                             send_email becomes a send_email; any other
                             offered tool the answer names is called.
                             deaf: goes straight to its answer
  after that                 answers in words

STANDIN, READ_TOOL and READ_ARGS come from the environment. Standard library
only, on the pinned python:3.13-alpine.
"""
import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STANDIN = os.environ.get("STANDIN", "deaf")
READ_TOOL = os.environ.get("READ_TOOL", "quarterly_report")
READ_ARGS = json.loads(os.environ.get("READ_ARGS", "{}"))
URL = re.compile(r"https?://[^\s\"'<>|,]+")
EMAIL = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
CUSTOMER = re.compile(r"\bC[0-9]{4}\b")


def call(n, name, arguments):
    return {"id": "call_%d" % n, "type": "function",
            "function": {"name": name, "arguments": json.dumps(arguments)}}


def asked(text, offered, task):
    """The calls a tool's answer asks for, in the order it names them."""
    calls = []
    names = [t["function"]["name"] for t in offered]
    if "http_request" in names:
        for url in URL.findall(text):
            calls.append(("http_request", {"method": "POST", "url": url.rstrip(".,;)"), "body": task}))
    if "send_email" in text:
        for to in EMAIL.findall(text):
            calls.append(("send_email", {"to": to.rstrip("."), "subject": "As requested", "body": text[:400]}))
    for t in offered:
        name = t["function"]["name"]
        if name in (READ_TOOL, "http_request", "send_email") or not re.search(r"\b%s\b" % re.escape(name), text):
            continue
        args = {}
        for prop in (t["function"].get("parameters") or {}).get("properties", {}):
            found = CUSTOMER.search(text)
            args[prop] = found.group(0) if prop == "customer_id" and found else "1"
        calls.append((name, args))
    return calls


def decide(body):
    messages = body.get("messages", [])
    offered = body.get("tools") or []
    task = next((m.get("content") or "" for m in messages if m.get("role") == "user"), "")
    answers = [m.get("content") or "" for m in messages if m.get("role") == "tool"]
    turns = sum(1 for m in messages if m.get("role") == "assistant")
    if not answers:
        return None, [call(1, READ_TOOL, READ_ARGS)]
    if STANDIN == "obedient" and turns == 1:
        calls = asked(answers[0], offered, task)
        if calls:
            return None, [call(i + 2, name, args) for i, (name, args) in enumerate(calls)]
    return "The tool answered: " + answers[0].split(". ")[0][:160] + ".", []


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.reply({"status": "ok", "standin": STANDIN})

    def do_POST(self):
        size = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(size) or b"{}")
        except ValueError:
            body = {}
        content, tool_calls = decide(body)
        message = {"role": "assistant", "content": content}
        if tool_calls:
            message["tool_calls"] = tool_calls
        self.reply({"object": "chat.completion", "model": STANDIN,
                    "choices": [{"index": 0, "message": message,
                                 "finish_reason": "tool_calls" if tool_calls else "stop"}],
                    "timings": {"prompt_n": 0, "cache_n": 0, "predicted_n": 0, "prompt_ms": 0.0, "predicted_ms": 0.0}})

    def reply(self, payload):
        raw = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("", 8080), Handler).serve_forever()
