.PHONY: build run stop probe clean

build:
	./scripts/bundle.sh

run:
	./scripts/run.sh

stop:
	@pkill -x Islet >/dev/null 2>&1 || true
	@echo "stopped"

probe:
	swift run mediaspike info

clean:
	rm -rf .build build
