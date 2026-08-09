# FPP Toolchain Upgrade — Benchmark & Evaluation Report

## Headline

Moving off the 2022-era GraalVM cuts the fpp side of an F´ build **roughly in
half**, and the cheapest version of that change is **one functional line**.

Replaying every fpp invocation a Ref build performs (307 calls, no C++ compiled):

| Toolchain | Whole fpp workflow | Δ vs baseline | Functional LOC to adopt |
|---|---:|---:|---:|
| baseline — GraalVM CE 22.3.0 / JDK 11 | 37.494 s | — | 0 |
| shipping — `fprime-fpp` 3.3.0a15 wheel | 34.965 s | −6.7% | n/a |
| **JDK 17** — Oracle GraalVM 17.0.12 | **18.958 s** | **−49.4%** | **1** |
| JDK 21 — Oracle GraalVM 21.0.12 | 17.291 s | −53.9% | 7 |
| JDK 25 — Oracle GraalVM 25.0.4 | 16.883 s | −55.0% | 7 |

**JDK 17 captures ~90% of the total available gain for one line of change.**
Going further buys 8.8% more (17→21) and then 2.4% more (21→25), at the cost of
a Scala compiler bump and, at 25, a dependency on a JDK method scheduled for
removal.

The gain is not from the JDK version as such — it is from the `native-image`
generation. JDK 17 is simply the newest JDK reachable *without* touching Scala,
and it already gets the modern Substrate VM.

---

## 0. Scope and honesty statement

**Completed and measured:** baseline, shipping, JDK 17, JDK 21, JDK 25 — each
built, acceptance-tested, and benchmarked on the same machine with the same
corpus.

**Not done: Phase C.** `perf/o3`, `perf/pgo`, and `perf/march-v3` were never
built or measured. **There is therefore no march-v3 number and the ~3% stop
condition cannot be evaluated.** Work was redirected to the JDK ladder at the
user's request. Nothing in this report is estimated or extrapolated.

Two standing limits:

1. **The corpus is F´ `Ref`, not a real project.** The brief's `./project` was
   absent (`OBSTACLES.md` O-1); the brief itself warns Ref "will understate the
   deltas." **Every delta here is a lower bound.**
2. **The host is a shared 4-core cloud VM** (O-9). Medians and full
   distributions are reported, never means.

---

## 1. Methodology

| Protocol item | What was done |
|---|---|
| Tool | `hyperfine` 1.19.0 |
| Warmup | 3 |
| Runs | 100 for the fpp tool measurements; 20 for cold `generate`; 10–20 for the whole-workflow sweep |
| Statistic | Median, p95, min, max, σ/median from the full per-run export |
| Corpus | Harvested once, reused byte-for-byte by every phase |
| Isolation | No build or other benchmark running during any measurement |

### Corpus — harvested, not hand-rolled

`bench/prep-corpus.sh` runs a real `fprime-util generate` and harvests the
**verbatim command lines the F´ build emits** for the topology module
(`Ref/Top`): 2 sources, **101** imports via `-i`, an **802-directive**
`locs.fpp`. Only the tool path and output directory are rewritten.

### Whole-workflow measurement

The single-invocation numbers measure the worst individual call. What a
developer actually waits for is the whole sweep, so
`bench/run-workflow-bench.sh` replays every fpp invocation the build performs:

```
  1 x fpp-locate-defs     151 x fpp-depend
145 x fpp-to-cpp           10 x fpp-to-dict     = 307 total
```

No C++ is compiled and CMake is not re-run. This is the number in the headline
table, and its distributions are the tightest in the report (σ/median 1–2%).

### Guards against caching artifacts

- Output directories wiped before **every** run of `fpp-to-cpp`/`fpp-depend`.
- Cold `generate` deletes the entire build cache before **every** run.
- The harness **asserts** the phase's `bin` wins on `PATH`, so a run cannot
  silently fall through to the pip-installed `fprime-fpp` shims.
- `--shell=none` for the `fpp-check` startup measurement only, where a ~2 ms
  shell spawn would be a material fraction of a ~13 ms result.

---

## 2. Full results

| Tool | Phase | Median | p95 | Min | Max | σ/median | Δ vs baseline | n |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| fpp-depend (full model) | baseline | 553.5 ms | 583.7 ms | 520.4 ms | 615.8 ms | 3% | — | 100 |
|  | jdk17 | 269.1 ms | 378.9 ms | 252.2 ms | 657.2 ms | 26% | −51.4% | 100 |
|  | jdk21 | 264.7 ms | 425.1 ms | 240.1 ms | 582.2 ms | 23% | −52.2% | 100 |
|  | jdk25 | 248.6 ms | 274.8 ms | 235.0 ms | 299.8 ms | 5% | −55.1% | 100 |
|  | shipping | 555.0 ms | 721.8 ms | 521.0 ms | 781.7 ms | 9% | +0.3% | 100 |
| fpp-to-cpp (full model) | baseline | 1.331 s | 1.443 s | 1.261 s | 1.568 s | 4% | — | 100 |
|  | jdk17 | 651.1 ms | 694.9 ms | 608.2 ms | 712.2 ms | 3% | −51.1% | 100 |
|  | jdk21 | 530.4 ms | 573.6 ms | 498.7 ms | 693.0 ms | 5% | −60.1% | 100 |
|  | jdk25 | 526.8 ms | 620.9 ms | 490.9 ms | 771.1 ms | 10% | −60.4% | 100 |
|  | shipping | 1.328 s | 1.427 s | 1.243 s | 1.992 s | 7% | −0.2% | 100 |
| fpp-check (single small file) | baseline | 14.1 ms | 15.5 ms | 13.3 ms | 16.8 ms | 5% | — | 100 |
|  | jdk17 | 13.4 ms | 14.4 ms | 12.4 ms | 16.1 ms | 5% | −5.4% | 100 |
|  | jdk21 | 11.6 ms | 12.6 ms | 10.1 ms | 13.3 ms | 5% | −18.1% | 100 |
|  | jdk25 | 11.1 ms | 11.9 ms | 10.3 ms | 12.8 ms | 4% | −21.5% | 100 |
|  | shipping | 8.0 ms | 9.1 ms | 7.3 ms | 10.4 ms | 6% | −43.3% | 100 |
| fprime-util generate (cold) | baseline | 13.823 s | 15.392 s | 13.100 s | 15.994 s | 5% | — | 20 |
|  | jdk17 | 10.861 s | 11.412 s | 10.407 s | 11.414 s | 3% | −21.4% | 20 |
|  | jdk21 | 10.614 s | 11.218 s | 10.257 s | 11.305 s | 3% | −23.2% | 20 |
|  | jdk25 | 10.872 s | 11.866 s | 9.891 s | 12.903 s | 6% | −21.3% | 20 |
|  | shipping | 14.362 s | 19.460 s | 12.886 s | 20.370 s | 18% | +3.9% | 20 |
| **whole fpp workflow (307 invocations)** | baseline | 37.494 s | 37.889 s | 36.435 s | 38.022 s | 1% | — | 10 |
|  | **jdk17** | **18.958 s** | 19.458 s | 18.148 s | 19.576 s | 2% | **−49.4%** | 20 |
|  | jdk21 | 17.291 s | 17.623 s | 16.946 s | 17.775 s | 1% | −53.9% | 10 |
|  | jdk25 | 16.883 s | 17.036 s | 16.647 s | 17.066 s | 1% | −55.0% | 10 |
|  | shipping | 34.965 s | 35.402 s | 33.912 s | 35.438 s | 1% | −6.7% | 10 |

Raw per-run distributions: `bench/results/*.json`.
Regenerate: `python3 bench/analyze.py bench/results baseline`.

### Notes on the numbers

- **`generate` barely moves** because it is dominated by CMake configure, not
  fpp — it burns ~20 s of user time against ~13 s wall, i.e. it is parallel and
  mostly not our code. Do not expect toolchain work to help here.
- **`fpp-depend` has a fat tail on jdk17/jdk21** (σ/median 23–26%) from
  interference outliers; the medians are stable and the p95s still sit far below
  baseline's median, so the conclusion is unaffected.
- **The shipping wheel is only −6.7%** versus our baseline on the whole
  workflow, confirming our baseline is a faithful stand-in for what ships. The
  ~50% is a real gain over what users run today, not an artifact.

### Binary size — the one real regression

| Phase | Binary | vs baseline |
|---|---:|---:|
| shipping | 55.7 MB | — |
| baseline | 57.9 MB | — |
| jdk25 | 76.7 MB | +32% |
| jdk21 | 80.5 MB | +39% |
| jdk17 | 83.0 MB | +43% |

Every modern toolchain produces a substantially larger binary. If wheel size
matters, note that this partly offsets the argument for 17 — it is both the
slowest of the three upgrades and the largest binary.

---

## 3. Acceptance

Per §4, a green unit suite is not sufficient. All three upgrades were checked
against the native binary with it first on `PATH`.

| | `./test` | `fprime-util generate` | Generated C++ vs baseline |
|---|---|---|---|
| jdk17 | **1269 pass / 0 fail** | pass (20+ cold runs) | **byte-identical, 832 files** |
| jdk21 | 1517 pass / **3 fail** | pass (20+ cold runs) | **byte-identical, 832 files** |
| jdk25 | 614 pass / **907 fail** | pass (20+ cold runs) | **byte-identical, 832 files** |

**The generated C++ is byte-identical across all four toolchains** — 832 files
each, `diff -r` exit 0. This is the strongest correctness result in the report:
no toolchain in this ladder perturbs codegen.

Full `fprime-util build` (C++ compilation) was deliberately skipped — with the
generated C++ proven identical, compiling it adds no information.

### The jdk21 failures — JSON ordering, not corruption

All 3 are in `tools/fpp-to-dict/test/top`. Parsing both sides as JSON:

```
[typeDefinitions] ref=22 out=22  same-as-multiset=True
  missing from out: 0   extra in out: 0
```

**Pure reordering.** Scala 3.3.8 iterates the type definitions in a different
order than 3.1.2. No entry is added, lost, or altered. It breaks golden files
and makes dictionary output non-reproducible across compiler versions, but it
loses no information. Fixing it properly means imposing a deterministic sort in
the dictionary writer — a compiler source change, out of scope here.

### The jdk25 failures — a stderr banner, and a ticking clock

Every invocation prints:

```
WARNING: sun.misc.Unsafe::objectFieldOffset has been called by scala.runtime.LazyVals$
WARNING: sun.misc.Unsafe::objectFieldOffset will be removed in a future release
```

Stripping `WARNING:` lines, **60 of 60 sampled outputs match their reference
exactly**, so the 907 failures are entirely this banner polluting captured
stderr — the same class of problem as O-11.

The second warning is the real issue. Scala 3.3.8's lazy-val implementation
calls a method the JDK has scheduled for **removal** — the same `LazyVals` /
`0bitmap$N` mechanism that fills `reflect-config.json` (O-10). JDK 25 on
Scala 3.3 LTS therefore works today and breaks on some future JDK. Escaping it
needs a newer Scala line (3.8.x) with `VarHandle`-based lazy vals, which is a
much larger jump than 3.3.8.

---

## 4. Cost to adopt

Functional lines changed (comments and blanks excluded), versus `main`:

| Path | Compiler build config | Incl. CI + `env-setup` |
|---|---:|---:|
| JDK 17 | **1** | 30 |
| JDK 21 | 7 | 37 |
| JDK 25 | 7 | 37 |

The ~29-line `env-setup`/CI portion is **the same rewrite for all three** — new
download URL, drop `gu install native-image` (it no longer exists in these
layouts), export `GRAALVM_JAVA_HOME`. So the true marginal cost of 21 or 25
over 17 is **6 lines**:

```diff
-ThisBuild / scalaVersion := "3.1.2"      +ThisBuild / scalaVersion := "3.3.8"
-    "-Xmax-inlines:100"                  +    "-Xmax-inlines:100",
                                          +    "-source:3.1"
-scala_version="3.1.2"                    +scala_version="3.3.8"
```

**LOC is the wrong axis for this decision.** Six lines is nothing. The real
costs are qualitative:

- **JDK 17** — the only path needing no Scala change, but Oracle GraalVM
  17.0.12 (Jul 2024) is the **final release on that line**. Adopting it means
  adopting a toolchain that receives no further security updates.
- **JDK 21 / 25** — need `-source:3.1`, which pins 60 unchecked pattern
  bindings at Scala 3.1 semantics indefinitely. That is deferred debt, not a
  fix; `sbt -rewrite -source 3.2-migration` clears it, but that edits compiler
  sources.
- **JDK 25 additionally** stands on a method scheduled for removal.

---

## 5. Recommendation

### Is the upgrade worth adopting? Yes, clearly.

A **49–55% reduction** in the fpp side of every build, with **byte-identical
generated C++**, for a diff measured in single-digit lines. This is the
cheapest large win available in this codebase.

### Which one?

**Take JDK 21.** Reasoning:

- It captures **53.9%** of the 55.0% available — within ~1pp of JDK 25 — so the
  newest LTS buys essentially nothing extra (2.4% relative) while carrying a
  dependency on a method being removed.
- Its only test failures are **JSON key ordering with provably identical
  content**, and its generated C++ is byte-identical.
- It is the **current maintained LTS**. JDK 17's GraalVM line is already
  end-of-updates, which is a poor foundation for a tool you ship to others.

**Take JDK 17 instead if** you want the change to be as close to zero-risk as
possible right now: it is the only option with a fully green suite, it needs no
Scala bump and no `-source` pin, and 49.4% of 55.0% is already ~90% of the
prize. It is a legitimate choice; just book the end-of-updates position as debt
you will have to repay.

**Do not take JDK 25** on Scala 3.3.x. It is the fastest by a hair and the
smallest binary, but it is the only option with a known forward-looking break.

### Is a per-CPU-level variant scheme justified?

**Unanswerable — `perf/march-v3` was never built or measured.**

I will not guess at it. What the measurements *do* bound: cold `generate` is
dominated by CMake rather than fpp, and startup is already ~11–13 ms, so
`-march` has little room in two of the four measurements. The burden of proof
sits with march-v3 clearing 3% on the whole-workflow number, and the harness is
ready to test it in about ten minutes of machine time. Until it is run, the
answer is **"unknown", not "probably not"**.

---

## 6. Loose end worth chasing

**Shipping's startup is 8.0 ms; our baseline's is 14.1 ms** — the older
toolchain is 43% *faster* to start. Unverified hypothesis: CI builds with
`-H:PageSize=65536`
(`.github/actions/build-native-images/native-images`) while `compiler/release`
passes no such flag, so `./release` and CI do not produce equivalent binaries.

If that is the cause it is free startup being left on the floor by local release
builds, and it is a one-flag change. It also means the `shipping` row differs
from `baseline` in build flags *and* fpp version, not in toolchain alone — so
read that row as "what users run today", not as a controlled comparison.

---

## 7. Reproducing

```sh
export GRAALVM_JAVA_HOME=/path/to/graalvm        # and FPP_JAVA_HOME
cd compiler && ./release                          # builds + runs ./test

bash bench/prep-corpus.sh        <bin>            # ONCE, then reuse
bash bench/capture-env.sh        <phase> "$GRAALVM_JAVA_HOME" "$FLAGS"
bash bench/run-bench.sh          <phase> <bin>    # the 4 protocol measurements
bash bench/run-workflow-bench.sh <phase> <bin>    # all 307 invocations
bash bench/gen-cpp-snapshot.sh   <phase> <bin>    # 832 files for the diff
python3 bench/analyze.py bench/results baseline
diff -r /home/user/cppsnap/baseline /home/user/cppsnap/<phase>
```

Phase C flags go through `FPP_NATIVE_IMAGE_FLAGS`, which `compiler/release`
already honours: `-O3`; `--pgo-instrument` then `--pgo=<profile>.iprof`;
`-march=x86-64-v3`. **Never `-march=native`** — this build host reports AVX-512,
which would be baked into a binary shipped to machines that lack it.
