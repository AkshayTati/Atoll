.PHONY: build run stop install probe signing clean

build:
	./scripts/bundle.sh

run:
	./scripts/run.sh

install:
	./scripts/install.sh

stop:
	@pkill -x Islet >/dev/null 2>&1 || true
	@if [ -f build/log.pid ]; then kill "$$(cat build/log.pid)" >/dev/null 2>&1 || true; fi
	@echo "stopped"

signing:
	./scripts/setup-signing.sh

probe:
	swift run mediaspike info

clean:
	rm -rf .build build
