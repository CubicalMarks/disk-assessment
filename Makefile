.DEFAULT_GOAL := help
.PHONY: help build dmg release run lint test check

help:
	@printf 'make build    Build the macOS app\nmake dmg      Build a drag-to-Applications disk image and checksum\nmake release  Validate, package and upload a draft GitHub release\nmake run      Build and open the app\nmake lint     Check source syntax and configuration\nmake test     Run fixture-based tests (no build required)\nmake check    Run source checks, build/signature verification and tests\n'

build:
	bash scripts/build-app.sh

dmg:
	bash scripts/build-dmg.sh

release:
	bash scripts/release.sh $(RELEASE_ARGS)

run: build
	open "dist/Disk Assessment.app"

lint:
	bash scripts/lint.sh

test:
	bash scripts/test-app.sh

check: lint
	$(MAKE) build
	$(MAKE) test
