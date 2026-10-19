.DEFAULT_GOAL := help
.PHONY: help build lint test check

help:
	@printf 'make build  Build the macOS app\nmake lint   Check source syntax and configuration\nmake test   Run fixture-based tests (no build required)\nmake check  Run source checks, build/signature verification and tests\n'

build:
	bash scripts/build-app.sh

lint:
	bash scripts/lint.sh

test:
	bash scripts/test-app.sh

check: lint
	$(MAKE) build
	$(MAKE) test
