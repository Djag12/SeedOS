#!/bin/sh
set -eu
cd "$(dirname "$0")"
outdir=build
asmflags=
cflags=
if [ "${BENCHMARK:-0}" = 1 ]; then
 outdir=build-bench
 asmflags="--defsym BENCHMARK=1"
 cflags=-DBENCHMARK
fi
export outdir
mkdir -p "$outdir"
as --64 start.S -o "$outdir"/start.o
as --64 $asmflags interrupts.S -o "$outdir"/interrupts.o
gcc $cflags -m64 -Os -mno-red-zone -mno-sse -mno-mmx -ffreestanding -fno-pie -fno-stack-protector -fno-builtin -Wall -Wextra -c kernel.c -o "$outdir"/kernel.o
ld -m elf_x86_64 -T link.ld "$outdir"/start.o "$outdir"/kernel.o "$outdir"/interrupts.o -o "$outdir"/kernel.elf
objcopy -O binary "$outdir"/kernel.elf "$outdir"/kernel.bin
as --32 boot.S -o "$outdir"/boot.o
ld -m elf_i386 -Ttext 0x7c00 --oformat binary -e _start "$outdir"/boot.o -o "$outdir"/boot.bin
python3 - <<'PY'
from pathlib import Path
import os
b=Path(os.environ["outdir"])
k=(b/'kernel.bin').read_bytes()
assert len(k)<=8704,len(k)
a=bytearray(1474560);a[:512]=(b/'boot.bin').read_bytes();a[512:512+len(k)]=k;(b/'seedos64.img').write_bytes(a)
print('kernel bytes',len(k))
PY
