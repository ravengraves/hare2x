#!/usr/bin/env bash
# Generate AT&T x86_64 assembly from a C file with -O0 (for readable debug output).
set -euo pipefail
script_dir=$(cd "$(dirname "$0")" && pwd)
project_root=$(cd "$script_dir/.." && pwd)

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <c-file> [out.s]" >&2
  exit 1
fi

src=$1
out=${2:-"$project_root/x86_64/test.s"}

CC=${CC:-clang}

$CC -O0 "$src" -S -o "$out" \
  -masm=att \
  -ffreestanding -nostdlib -nostartfiles -nodefaultlibs \
  -fno-builtin -fno-ident -fno-asynchronous-unwind-tables -fno-unwind-tables \
  -fno-stack-protector -fverbose-asm -fno-PIC -static -msse4.2 \
  -ffunction-sections -fdata-sections

wc -l "$out"
cat "$out"
