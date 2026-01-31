#!/bin/sh
# Test script for Pika GLSL backend and triangle demo

set -e
cd "$(dirname "$0")/.."

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' NC='\033[0m'
PASS=0 FAIL=0 SKIP=0

pass() { printf "${GREEN}PASS${NC}\n"; PASS=$((PASS + 1)); }
fail() { printf "${RED}FAIL${NC} ($1)\n"; FAIL=$((FAIL + 1)); }
skip() { printf "${YELLOW}SKIP${NC} ($1)\n"; SKIP=$((SKIP + 1)); }

TMPDIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMPDIR"
  stty sane 2>/dev/null || true
  tput cnorm 2>/dev/null || true
}
trap cleanup EXIT INT TERM HUP

Xvfb=$(command -v xvfb-run 2>/dev/null || true)
GLSLANG=$(command -v glslangValidator 2>/dev/null || true)
GLSLANG_OPTS="--glsl-version 100"
NODE=$(command -v node 2>/dev/null || true)

run_gl() {
  if [ -z "${DISPLAY}" ] && [ -n "$Xvfb" ]; then
    xvfb-run -s "-screen 0 1280x720x24" "$@"
  else
    "$@"
  fi
}

echo "=== Building GLSL demo ==="
if ! make -C glsl >/dev/null; then
  fail "glsl build failed"
  exit 1
fi
pass
echo

echo "=== Building pika2c ==="
if ! make pika2c >/dev/null; then
  fail "pika2c build failed"
  exit 1
fi
pass
echo

compile_shader() {
  stage="$1"
  input="$2"
  output="$3"
  {
    printf -- "-T glsl\n-S %s\n" "$stage"
    cat "$input" glsl/gl.pka
  } | build/pika2c > "$output"
}

echo "=== Demo Smoke Test ==="
demo_vert="$TMPDIR/demo.vert"
demo_frag="$TMPDIR/demo.frag"
if ! compile_shader vertex test/glsl/003_demo_vertex.pka "$demo_vert"; then
  fail "demo vertex compile"
  exit 1
fi
if ! compile_shader fragment test/glsl/003_demo_fragment.pka "$demo_frag"; then
  fail "demo fragment compile"
  exit 1
fi
demo_log="$TMPDIR/demo_terminal.txt"
demo_status="$TMPDIR/demo_status"
rm -f "$demo_status"
( LIBGL_ALWAYS_SOFTWARE=1 run_gl glsl/triangle_demo --headless --seconds 0.1 \
  --terminal --terminal-fps 1 --term-cols 40 --term-rows 20 \
  --vertex "$demo_vert" --fragment "$demo_frag"; echo $? > "$demo_status" ) 2>&1 | tee "$demo_log"
if [ ! -f "$demo_status" ] || [ "$(cat "$demo_status")" -ne 0 ]; then
  fail "demo run failed"
else
  if python3 - "$demo_log" <<'PY'
import re
import sys
path = sys.argv[1]
data = open(path, "rb").read().decode("utf-8", "ignore")
pattern = re.compile(r"\x1b\[(?:3|4)8;2;(\d+);(\d+);(\d+)m")
colors = pattern.findall(data)
non_black = sum(1 for r, g, b in colors if int(r) or int(g) or int(b))
if non_black < 20:
    print(f"demo output too blank: {non_black} colored cells")
    sys.exit(1)
PY
  then
    pass
  else
    fail "demo output too blank"
  fi
fi
echo

echo "=== Node GLSL Demo Test ==="
if [ -n "$NODE" ]; then
  if node test/test_glsl_node.js; then
    pass
  else
    fail "node demo"
  fi
else
  skip "node missing"
fi
echo

validate_shader() {
  stage="$1"
  input="$2"
  if [ -z "$GLSLANG" ]; then
    return 0
  fi
  if [ "$stage" = "vertex" ]; then
    stage_opt="vert"
  else
    stage_opt="frag"
  fi
  "$GLSLANG" $GLSLANG_OPTS -S "$stage_opt" "$input" >/dev/null 2>&1
}

validate_link() {
  vert="$1"
  frag="$2"
  if [ -z "$GLSLANG" ]; then
    return 0
  fi
  "$GLSLANG" $GLSLANG_OPTS -l "$vert" "$frag" >/dev/null 2>&1
}

echo "=== GLSL Shader Tests ===" && echo
for vfile in test/glsl/*_vertex.pka; do
  [ -f "$vfile" ] || continue
  base=$(basename "$vfile" _vertex.pka)
  ffile="test/glsl/${base}_fragment.pka"
  if [ ! -f "$ffile" ]; then
    skip "$base (missing fragment)"
    continue
  fi
  printf "Testing %-40s " "$base..."
  vout="$TMPDIR/${base}.vert"
  fout="$TMPDIR/${base}.frag"
  if ! compile_shader vertex "$vfile" "$vout"; then
    fail "vertex compile"
    continue
  fi
  if ! compile_shader fragment "$ffile" "$fout"; then
    fail "fragment compile"
    continue
  fi
  if ! validate_shader vertex "$vout"; then
    fail "vertex validate"
    continue
  fi
  if ! validate_shader fragment "$fout"; then
    fail "fragment validate"
    continue
  fi
  if ! validate_link "$vout" "$fout"; then
    fail "link validate"
    continue
  fi
  if LIBGL_ALWAYS_SOFTWARE=1 run_gl glsl/triangle_demo --headless --seconds 0.1 \
    --terminal --terminal-fps 1 --term-cols 40 --term-rows 20 \
    --vertex "$vout" --fragment "$fout" >/dev/null 2>&1; then
    pass
  else
    fail "render failed"
  fi
done

echo && echo "=== Summary ==="
TOTAL=$((PASS + FAIL + SKIP))
printf "Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}  Skipped: ${YELLOW}$SKIP${NC}  Total: $TOTAL\n"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
