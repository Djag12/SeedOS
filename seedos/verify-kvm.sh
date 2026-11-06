#!/bin/sh
# A hardware KVM measurement, independent of the compiler/renderer dependencies.
set -eu
cd "$(dirname "$0")/.."
python3 - <<'PY'
import fcntl, os, platform
if platform.machine() != 'x86_64':
    raise SystemExit('The x86-64 KVM benchmark requires an x86-64 host.')
try:
    fd = os.open('/dev/kvm', os.O_RDWR)
except OSError as exc:
    raise SystemExit(f'KVM preflight blocked before benchmarking: {exc}')
try:
    if fcntl.ioctl(fd, 0xAE00, 0) != 12:
        raise SystemExit('Unsupported KVM API.')
finally:
    os.close(fd)
PY
make os
python3 seedos/test.py > results/seedos.pending.json
mv results/seedos.pending.json results/seedos.json
ACCEL=kvm BENCH_RUNS=5 make os-benchmark
python3 - <<'PY'
import json
from pathlib import Path
data = json.loads(Path('results/seedos_benchmark.json').read_text())
print(json.dumps(data, indent=2))
if data['accelerator'] != 'kvm' or data['runs'] != 5 or not data['exact_kvm_target_verified']:
    raise SystemExit('The measured median did not reach the resume threshold.')
PY
