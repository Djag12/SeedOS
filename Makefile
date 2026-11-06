.PHONY: all demo test benchmark hardware os os-benchmark
all: os
os:
	sh seedos/build.sh
test: os
	python3 seedos/test.py
benchmark: os-benchmark
os-benchmark:
	BENCHMARK=1 sh seedos/build.sh
	python3 seedos/benchmark.py > results/seedos_benchmark.pending.json && mv results/seedos_benchmark.pending.json results/seedos_benchmark.json
hardware:
	sh seedos/verify-kvm.sh
