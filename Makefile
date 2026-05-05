# ShipItSwifty — Linux / Docker convenience targets
#
# These targets let you build and test the Linux-compatible subset of the package
# without needing a local Swift toolchain — just Docker.
#
# macOS-only targets skipped on Linux:
#   XcodeBuildKitTests, XcodeGenKitTests, IntegrationTests

SWIFT_IMAGE := swift:6.3.1-noble

# Mount the working directory into the container rather than baking a new image
# every time.  Fast for iterative dev; no docker build step needed.
DOCKER_RUN     := docker run --rm -v "$(PWD):/workspace" -w /workspace $(SWIFT_IMAGE)
DOCKER_RUN_IT  := docker run --rm -it -v "$(PWD):/workspace" -w /workspace $(SWIFT_IMAGE)

# Linux-only test skip list (targets that require macOS tooling)
LINUX_SKIP := --skip IntegrationTests --skip XcodeBuildKitTests --skip XcodeGenKitTests

# ── Direct-mount targets (no docker build required) ──────────────────────────

.PHONY: build-linux
build-linux:  ## Build the package on Linux (direct mount)
	$(DOCKER_RUN) swift build

.PHONY: test-linux
test-linux:  ## Run Linux-compatible tests (direct mount)
	$(DOCKER_RUN) swift test $(LINUX_SKIP)

.PHONY: test-linux-coverage
test-linux-coverage:  ## Run Linux-compatible tests with code coverage (direct mount)
	$(DOCKER_RUN) swift test $(LINUX_SKIP) --enable-code-coverage

.PHONY: shell-linux
shell-linux:  ## Open an interactive shell inside the Linux container (direct mount)
	$(DOCKER_RUN_IT) /bin/bash

# ── Image-based targets (uses Dockerfile with cached dep layer) ───────────────

.PHONY: docker-build
docker-build:  ## Build the shipitswifty-dev Docker image (caches SPM deps as a layer)
	docker build -t shipitswifty-dev .

.PHONY: docker-test
docker-test: docker-build  ## Run Linux-compatible tests inside the built image
	docker run --rm shipitswifty-dev swift test $(LINUX_SKIP)

.PHONY: docker-shell
docker-shell: docker-build  ## Open an interactive shell inside the built image
	docker run --rm -it shipitswifty-dev /bin/bash

# ── Help ──────────────────────────────────────────────────────────────────────

.PHONY: help
help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-26s\033[0m %s\n", $$1, $$2}'
