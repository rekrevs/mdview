CONFIGURATION ?= debug
INSTALL_DIR ?= $(HOME)/Applications

.PHONY: build release bundle install test check test-swift test-renderer gui-test validate-bundle clean

build:
	./scripts/swift-tool.sh build -c $(CONFIGURATION)

release:
	$(MAKE) bundle CONFIGURATION=release

bundle: build
	./bundle.sh --configuration $(CONFIGURATION)

install: CONFIGURATION = release
install: bundle
	./scripts/install.sh "$(INSTALL_DIR)"

test: test-swift test-renderer

check: test

test-swift:
	./scripts/swift-tool.sh test

test-renderer: Tests/Renderer/node_modules/jsdom/package.json
	npm --prefix Tests/Renderer test

Tests/Renderer/node_modules/jsdom/package.json: Tests/Renderer/package.json Tests/Renderer/package-lock.json
	npm --prefix Tests/Renderer ci --ignore-scripts --no-audit --no-fund

gui-test: bundle
	python scripts/check-reader.py

validate-bundle:
	./scripts/validate-bundle.sh mdview.app

clean:
	./scripts/swift-tool.sh package clean
	rm -rf mdview.app
