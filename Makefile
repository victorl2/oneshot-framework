ONESHOT_VERSION := $(shell cat VERSION)
SANDBOX_IMAGE   := oneshot-sandbox:$(ONESHOT_VERSION)
SANDBOX_LATEST  := oneshot-sandbox:latest
TEST_RUN_DIR    := /tmp/oneshot-test-run

.PHONY: help install install-dry uninstall build-sandbox test-sandbox clean version

help:
	@echo "Oneshot framework — v$(ONESHOT_VERSION)"
	@echo ""
	@echo "Targets:"
	@echo "  install         Install commands/agents/templates into ~/.claude/"
	@echo "  install-dry     Show what install would do, make no changes"
	@echo "  uninstall       Remove all installed files from ~/.claude/"
	@echo "  build-sandbox   Build the sandbox Docker image ($(SANDBOX_LATEST))"
	@echo "  test-sandbox    Run the sandbox image locally with the demo agent"
	@echo "                  and print the resulting status.jsonl / heartbeats.jsonl"
	@echo "  clean           Remove test artifacts"
	@echo "  version         Print the framework version"

install:
	@./install.sh

install-dry:
	@./install.sh --dry-run

uninstall:
	@./install.sh --uninstall

build-sandbox:
	docker build -t $(SANDBOX_IMAGE) -t $(SANDBOX_LATEST) sandbox/

test-sandbox: build-sandbox
	@rm -rf $(TEST_RUN_DIR)
	@mkdir -p $(TEST_RUN_DIR)
	@echo "=== running sandbox demo ==="
	docker run --rm \
		-v $(TEST_RUN_DIR):/workspace/run \
		-e ONESHOT_MODEL=demo \
		-e ONESHOT_HEARTBEAT_INTERVAL_S=2 \
		$(SANDBOX_LATEST)
	@echo ""
	@echo "=== status.jsonl (semantic events) ==="
	@cat $(TEST_RUN_DIR)/status.jsonl
	@echo ""
	@echo "=== heartbeats.jsonl (compact telemetry) ==="
	@cat $(TEST_RUN_DIR)/heartbeats.jsonl
	@echo ""
	@echo "=== current.json (live snapshot) ==="
	@cat $(TEST_RUN_DIR)/current.json
	@echo ""
	@echo "=== file sizes ==="
	@ls -la $(TEST_RUN_DIR)

clean:
	rm -rf $(TEST_RUN_DIR)

version:
	@echo $(ONESHOT_VERSION)
