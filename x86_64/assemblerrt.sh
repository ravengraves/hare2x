#!/usr/bin/env bash
# Build a freestanding test object against lib/pika/rt.c for x86_64.
set -euo pipefail
script_dir=$(cd "$(dirname "$0")" && pwd)
project_root=$(cd "$script_dir/.." && pwd)

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <c-file> [out.o]" >&2
  exit 1
fi

src=$1
out=${2:-"$project_root/x86_64/test.o"}

CC=${CC:-clang}

$CC -Os "$src" "$project_root/lib/pika/rt.c" -o "$out" \
  -ffreestanding -nostdlib -nostartfiles -nodefaultlibs \
  -fno-builtin -fno-ident -fno-asynchronous-unwind-tables -fno-unwind-tables \
  -fno-stack-protector -Wl,--build-id=none,-z,noseparate-code \
  -fno-PIC -static -fuse-ld=lld -msse4.2 \
  -ffunction-sections -fdata-sections

objdump -D "$out" | wc -l
objdump -D "$out"
