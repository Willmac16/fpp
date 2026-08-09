#!/bin/bash
# ----------------------------------------------------------------------
# Capture the exact toolchain of a phase.
#   usage: capture-env.sh <phase-name> <graalvm-home> <native-image-flags>
# Writes bench/<phase>-env.txt
# ----------------------------------------------------------------------
set -u
PHASE="${1:?}"; GVM="${2:?}"; FLAGS="${3:-}"
BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
FPP=/home/user/fpp
OUT="$BENCH_DIR/$PHASE-env.txt"

{
  echo "phase:              $PHASE"
  echo "captured:           $(date -Is)"
  echo
  echo "--- source ---"
  echo "fpp git SHA:        $(cd $FPP && git rev-parse HEAD)"
  echo "fpp branch:         $(cd $FPP && git rev-parse --abbrev-ref HEAD)"
  echo "fprime git SHA:     $(cd /home/user/fprime && git rev-parse HEAD)"
  echo "FPP VERSION string: $(cd $FPP && . ./version.sh && echo $VERSION)"
  echo
  echo "--- JDK / GraalVM ---"
  echo "GRAALVM_JAVA_HOME:  $GVM"
  echo "java -version:"
  "$GVM/bin/java" -version 2>&1 | grep -v "Picked up" | sed 's/^/  /'
  echo "native-image --version:"
  "$GVM/bin/native-image" --version 2>&1 | grep -v "Picked up" | sed 's/^/  /'
  echo
  echo "--- Scala / sbt ---"
  echo "scalaVersion:       $(grep -o 'scalaVersion := \"[^\"]*\"' $FPP/compiler/build.sbt | head -1)"
  echo "sbt.version:        $(grep sbt.version $FPP/compiler/project/build.properties)"
  echo "sbt-assembly:       $(cat $FPP/compiler/project/assembly.sbt)"
  echo
  echo "--- native-image flags ---"
  echo "FPP_NATIVE_IMAGE_FLAGS: $FLAGS"
  echo "fixed flags in compiler/release: --no-fallback --install-exit-handlers"
  echo "full command shape: native-image \$FPP_NATIVE_IMAGE_FLAGS --no-fallback --install-exit-handlers -jar bin/fpp.jar <out>"
  echo
  echo "--- C toolchain ---"
  cc --version 2>&1 | head -1 | sed 's/^/  /'
  echo
  echo "--- host ---"
  echo "CPU:                $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')"
  echo "cores:              $(nproc)"
  echo "mem:                $(free -g | awk '/^Mem:/{print $2}') GiB"
  echo "kernel:             $(uname -sr)"
} > "$OUT"
cat "$OUT"
