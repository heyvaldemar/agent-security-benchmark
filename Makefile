# The suite through a boundary on kind, CPU only, at no cloud cost.
# A shell for every recipe: macOS make 3.81 runs a simple recipe without one,
# and the PATH exported below then never reaches it.
SHELL := /usr/bin/env bash
BIN := $(CURDIR)/.cache/bin
export PATH := $(BIN):$(PATH)
# A kubeconfig of its own, so a run here never moves another cluster's context.
export KUBECONFIG := $(CURDIR)/.cache/kubeconfig

.PHONY: tools sources up test check down

tools:
	@./scripts/install-tools.sh >/dev/null

sources: tools
	./scripts/sources.sh flagship sandbox cypress

up: tools
	./scripts/up.sh sandbox
	./scripts/up.sh beside sandbox

test: tools
	./tests/e2e/run.sh sandbox obedient
	./tests/e2e/run.sh sandbox deaf

check: tools sources
	./scripts/validate.sh
	python3 tests/static/plant_violations.py

down: tools
	./scripts/up.sh down agent-sandbox
