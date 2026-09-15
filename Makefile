.PHONY: bootstrap build build-luapanda server client debug-console test bench
bootstrap:
	./scripts/bootstrap_skynet.sh
build:
	./scripts/linux/build.sh
build-luapanda:
	./scripts/linux/build_luapanda.sh
server:
	./scripts/linux/run_server.sh
client:
	./scripts/linux/run_client.sh
debug-console:
	./scripts/linux/debug_console.sh
test:
	./scripts/linux/test.sh
bench:
	./scripts/linux/benchmark_aoi.sh
