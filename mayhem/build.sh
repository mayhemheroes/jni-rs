#!/usr/bin/env bash
#
# jni-rs/mayhem/build.sh — build jni-rs's cargo-fuzz target(s) as sanitized libFuzzer binaries,
# replicating OSS-Fuzz's Rust path (cargo-fuzz + ASan via RUSTFLAGS -Zsanitizer=address).
#
# jni-rs is Rust bindings to the JNI; the fuzz target exercises the crate's PURE-RUST JNI
# type-signature parsers (jni::signature::JavaType / RuntimeMethodSignature) — no JVM required.
# The cargo-fuzz crate is ADDITIVE under mayhem/fuzz/ (upstream ships no fuzz/ dir), leaving the
# upstream tree untouched.
#
#   - cargo-fuzz ships its own libFuzzer runtime (the produced binary IS a libFuzzer target —
#     Mayhem runs it directly via `libfuzzer: true`);
#   - ASan is enabled the Rust way, through RUSTFLAGS `-Zsanitizer=address` (NOT clang's
#     $SANITIZER_FLAGS / CFLAGS — those don't apply to rustc). nightly is required for `-Zsanitizer`.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE. This first (CI,
# online) build populates the cargo registry under $CARGO_HOME=/opt/toolchains/rust/cargo; the
# re-run resolves crates from that cache (the rlenv runtime exports CARGO_NET_OFFLINE=true), so do
# NOT hard-code `--offline` here.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer (cargo's cc-built deps,
# e.g. libfuzzer-sys, do invoke clang).
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# DWARF < 4 debug-info contract (§6.2 item 10). Default forces DWARF version 2 so Mayhem triage /
# gdb can resolve project source lines (clang/rustc LLVM default to DWARF 5). The rlenv runtime may
# export RUST_DEBUG_FLAGS before re-running build.sh offline; the `:-` default only applies when the
# variable is unset or empty.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=--dwarf-version=2}"

cd "$SRC"

# ── DWARF < 4 enforcement (§6.2 item 10) ────────────────────────────────────────────────────────
# Rust's ASan runtime (librustc-nightly_rt.asan.a) is compiled with the nightly's bundled LLVM
# (DWARF 5 default) and is linked BEFORE the project code, so without intervention the first CU in
# .debug_info would be DWARF 5. Strip the ASan archive's debug sections once so it contributes no
# debug info; our project code (DWARF 2 via RUST_DEBUG_FLAGS) then appears first in .debug_info.
# The stripped .a is baked into the image, so the offline re-run reproduces the same result.
ASAN_RT="$(find "$RUSTUP_HOME/toolchains" -name "librustc-nightly_rt.asan.a" 2>/dev/null | head -1)"
if [ -n "$ASAN_RT" ] && [ -f "$ASAN_RT" ]; then
    echo "Stripping debug info from Rust ASan runtime to enforce DWARF < 4: $ASAN_RT"
    objcopy --strip-debug "$ASAN_RT"
fi

# libfuzzer-sys compiles libFuzzer from C++ via the cc crate; force DWARF 3 so those CUs also
# satisfy the check (the cc crate respects CFLAGS/CXXFLAGS). The flags are stable across the
# re-run, so cargo reuses the cached libfuzzer.a without recompiling.
export CFLAGS="${CFLAGS:+$CFLAGS }-gdwarf-3"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }-gdwarf-3"

# The cargo-fuzz crate lives under mayhem/fuzz/ (additive — upstream ships no fuzz/).
FUZZ_DIR="mayhem/fuzz"
FUZZ_TARGETS=(typesignature)
TRIPLE="x86_64-unknown-linux-gnu"

# Replicate OSS-Fuzz `compile` RUSTFLAGS for a libFuzzer+ASan Rust build. cargo-fuzz sets the ASan
# flag itself by default, but we set it explicitly so the behavior is pinned and visible. `--cfg
# fuzzing` matches what libfuzzer-sys expects. RUST_DEBUG_FLAGS adds DWARF 2 debug info for our Rust
# code; combined with the stripped ASan runtime this ensures the first .debug_info CU is < 4.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address ${RUST_DEBUG_FLAGS}"

echo "=== cargo fuzz build (image-default nightly toolchain, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"

# `-O` (release w/ opt) + `--debug-assertions` mirrors OSS-Fuzz's build.sh (catches overflow/debug
# asserts during fuzzing). Use the image's DEFAULT toolchain (the Dockerfile pins the nightly); a
# `+toolchain` override would make rustup try to install another channel into the locked /opt prefix.
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
done

# Resolve the cargo target dir robustly via `cargo metadata`.
TARGET_DIR="$(cargo metadata --no-deps --format-version 1 --manifest-path "$FUZZ_DIR/Cargo.toml" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["target_directory"])')"
echo "fuzz target_directory: $TARGET_DIR"

REL="$TARGET_DIR/$TRIPLE/release"
for t in "${FUZZ_TARGETS[@]}"; do
  bin="$REL/$t"
  if [ ! -x "$bin" ]; then
    echo "ERROR: expected fuzz binary not found at $bin" >&2
    ls -la "$REL" >&2 || true
    exit 1
  fi
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

echo "build.sh complete:"
ls -la /mayhem/typesignature 2>&1 || true
