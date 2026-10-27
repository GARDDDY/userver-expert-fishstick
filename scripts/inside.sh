#!/usr/bin/env bash
set -euo pipefail
RUNS="${1:-5}"
SVC=bench_service
CBA_TAG=v1.6.0
JOBS=4
WORK=/work
RES=$WORK/results
SRC=/tmp/$SVC
CC=clang-15
CXX=clang++-15

export CCACHE_DISABLE=1

install_tools() {
  echo "installing Clang Build Analyzer"
  if ! command -v "$CXX"; then
    apt-get update -qq && apt-get install -y -qq clang-15 lld-15
  fi
  if ! command -v ClangBuildAnalyzer; then
    git clone --depth 1 --branch "$CBA_TAG" https://github.com/aras-p/ClangBuildAnalyzer /tmp/cba
    cmake -S /tmp/cba -B /tmp/cba/build -DCMAKE_BUILD_TYPE=Release
    cmake --build /tmp/cba/build -j"$JOBS"
    export PATH=/tmp/cba/build:$PATH
  fi
}

cd /tmp
mkdir -p "$RES"; find "$RES" -mindepth 1 -delete

install_tools

{
  uname -a; 
  echo "nproc: $(nproc)"
  grep -m1 'model name' /proc/cpuinfo || true
  free -m; $CXX --version; g++ --version | head -1
  cmake --version | head -1; echo "ninja $(ninja --version 2>&1)"
  echo "runs per variant: $RUNS, jobs: $JOBS"
  echo "prebuilt userver: $(ls /usr/lib/libuserver-core.a)"
} > "$RES/environment.txt" 2>&1

if [ ! -d "$SRC" ]; then
  (cd /tmp && userver-create-service --grpc --mongo --postgresql "$SVC")
fi
{ echo; cat "$WORK/scripts/pch.cmake"; } >> "$SRC/CMakeLists.txt"

declare -A FLAGS=(
  [baseline_notrace]="-DBENCH_TRACE=OFF"
  [baseline]=""
  [pch_onetarg]="-DBENCH_PCH=per_target"
  [pch_general]="-DBENCH_PCH=shared"
)
VARIANTS=(baseline_notrace baseline pch_onetarg pch_general)

build_variant() {
  local variant=$1 i=$2 out=$RES/$1 bd=/tmp/build_$1
  local trace="-ftime-trace"
  [[ "${FLAGS[$variant]}" == *BENCH_TRACE=OFF* ]] && trace=""
  mkdir -p "$out"
  rm -rf "$bd"
  local tag="$i"; [ "$i" = 0 ] && tag=warmup
  echo "$variant run $tag"
  cmake -S "$SRC" -B "$bd" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX \
    -DCMAKE_CXX_FLAGS="$trace -Wno-unknown-warning-option" \
    -DUSERVER_USE_CCACHE=OFF \
    -DUSERVER_FEATURE_GRPC=ON -DUSERVER_FEATURE_MONGODB=ON -DUSERVER_FEATURE_POSTGRESQL=ON \
    ${FLAGS[$variant]/-DBENCH_TRACE=OFF/} \
    > "$out/configure_$tag.log" 2>&1
  local s e rc=0
  s=$(date +%s.%N)
  cmake --build "$bd" -j"$JOBS" -- -k 0 > "$out/build_$tag.log" 2>&1 || rc=$?
  e=$(date +%s.%N)
  [ "$rc" = 0 ] || echo "build exited with $rc ($variant/build_$tag.log)"
  [ "$i" = 0 ] && return
  awk "BEGIN{print $e - $s}" > "$out/wall_$i.txt"
  cp "$bd/.ninja_log" "$out/ninja_log_$i.txt"
  if [ -n "$trace" ]; then
    ClangBuildAnalyzer --all "$bd" "/tmp/capture_${variant}_$i.bin"
    ClangBuildAnalyzer --analyze "/tmp/capture_${variant}_$i.bin" > "$out/cba_report_$i.txt"
  fi
}

build_variant baseline 0
for i in $(seq 1 "$RUNS"); do
  for v in "${VARIANTS[@]}"; do build_variant "$v" "$i"; done
done

python3 "$WORK/scripts/summarize.py" "$RES" > "$RES/summary.md"
cat "$RES/summary.md"
echo "Done. $RES"
