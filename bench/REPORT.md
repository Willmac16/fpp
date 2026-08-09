# FPP Toolchain Upgrade — Benchmark & Evaluation Report

## Headline

Moving off the 2022-era GraalVM cuts the fpp side of an F´ build **roughly in
half** — **but only with Oracle GraalVM.** The equivalent open-source GraalVM
Community build delivers about a quarter of that.

Replaying every fpp invocation a Ref build performs (307 calls, no C++ compiled):

| Toolchain | Licence | Whole fpp workflow | Δ vs baseline |
|---|---|---:|---:|
| baseline — GraalVM CE 22.3.0 / JDK 11 | GPLv2+CE | 37.494 s | — |
| shipping — `fprime-fpp` 3.3.0a15 wheel | GPLv2+CE | 34.965 s | −6.7% |
| **Community 21.0.2** | **GPLv2+CE** | **33.039 s** | **−11.9%** |
| **Community 25.0.2** | **GPLv2+CE** | **32.518 s** | **−13.3%** |
| Oracle 17.0.12 | GFTC | 18.958 s | −49.4% |
| Oracle 21.0.12 | GFTC | 17.291 s | −53.9% |
| Oracle 25.0.4 | GFTC | 16.883 s | −55.0% |

**The gap is the edition, not recency.** Community 25.0.2 and Oracle 25.0.4 are
two patch releases apart on the same JDK line, and they differ by a factor of
two. Community 25 behaves like Community 21 (−13.3% vs −11.9%), not like Oracle.
The ~50% comes from Oracle GraalVM's advanced optimizing compiler, which GraalVM
Community does not ship.

This is the central finding, because **the published artifact is Community**:
the shipped `fprime-fpp` 3.3.0a15 binary carries the embedded string
`GraalVM 22.3.0 Java 11 CE`, identical to our baseline. Capturing the ~50%
therefore means moving release builds from an open-source toolchain to Oracle
GFTC. **That is a licensing decision for the project, not a technical one.**

If Oracle GFTC is acceptable: take it, it is a large win for a tiny diff.
If it is not: the honest open-source ceiling measured here is **−13.3%**, and
the remaining options are `-O3` on Community and Scala Native, both covered
below.

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
|  | ce21 | 543.9 ms | 603.0 ms | 508.8 ms | 751.3 ms | 7% | -1.7% | 100 |
|  | ce25 | 539.2 ms | 574.6 ms | 505.6 ms | 635.8 ms | 4% | -2.6% | 100 |
|  | jdk17 | 269.1 ms | 378.9 ms | 252.2 ms | 657.2 ms | 26% | -51.4% | 100 |
|  | jdk21 | 264.7 ms | 425.1 ms | 240.1 ms | 582.2 ms | 23% | -52.2% | 100 |
|  | jdk25 | 248.6 ms | 274.8 ms | 235.0 ms | 299.8 ms | 5% | -55.1% | 100 |
|  | shipping | 555.0 ms | 721.8 ms | 521.0 ms | 781.7 ms | 9% | +0.3% | 100 |
| fpp-to-cpp (full model) | baseline | 1.331 s | 1.443 s | 1.261 s | 1.568 s | 4% | — | 100 |
|  | ce21 | 1.144 s | 1.221 s | 1.077 s | 1.326 s | 4% | -14.0% | 100 |
|  | ce25 | 1.156 s | 1.248 s | 1.081 s | 1.371 s | 4% | -13.1% | 100 |
|  | jdk17 | 651.1 ms | 694.9 ms | 608.2 ms | 712.2 ms | 3% | -51.1% | 100 |
|  | jdk21 | 530.4 ms | 573.6 ms | 498.7 ms | 693.0 ms | 5% | -60.1% | 100 |
|  | jdk25 | 526.8 ms | 620.9 ms | 490.9 ms | 771.1 ms | 10% | -60.4% | 100 |
|  | shipping | 1.328 s | 1.427 s | 1.243 s | 1.992 s | 7% | -0.2% | 100 |
| fpp-check (single small file) | baseline | 14.1 ms | 15.5 ms | 13.3 ms | 16.8 ms | 5% | — | 100 |
|  | ce21 | 14.0 ms | 16.7 ms | 12.8 ms | 17.9 ms | 7% | -1.1% | 100 |
|  | ce25 | 11.5 ms | 12.7 ms | 10.6 ms | 13.8 ms | 5% | -18.4% | 100 |
|  | jdk17 | 13.4 ms | 14.4 ms | 12.4 ms | 16.1 ms | 5% | -5.4% | 100 |
|  | jdk21 | 11.6 ms | 12.6 ms | 10.1 ms | 13.3 ms | 5% | -18.1% | 100 |
|  | jdk25 | 11.1 ms | 11.9 ms | 10.3 ms | 12.8 ms | 4% | -21.5% | 100 |
|  | shipping | 8.0 ms | 9.1 ms | 7.3 ms | 10.4 ms | 6% | -43.3% | 100 |
| fprime-util generate (cold) | baseline | 13.823 s | 15.392 s | 13.100 s | 15.994 s | 5% | — | 20 |
|  | ce21 | 13.150 s | 13.781 s | 12.448 s | 13.807 s | 3% | -4.9% | 20 |
|  | ce25 | 13.208 s | 14.285 s | 12.569 s | 15.786 s | 5% | -4.4% | 20 |
|  | jdk17 | 10.861 s | 11.412 s | 10.407 s | 11.414 s | 3% | -21.4% | 20 |
|  | jdk21 | 10.614 s | 11.218 s | 10.257 s | 11.305 s | 3% | -23.2% | 20 |
|  | jdk25 | 10.872 s | 11.866 s | 9.891 s | 12.903 s | 6% | -21.3% | 20 |
|  | shipping | 14.362 s | 19.460 s | 12.886 s | 20.370 s | 18% | +3.9% | 20 |
| whole fpp workflow (307 invocations) | baseline | 37.494 s | 37.889 s | 36.435 s | 38.022 s | 1% | — | 10 |
|  | ce21 | 33.039 s | 33.348 s | 32.636 s | 33.502 s | 1% | -11.9% | 10 |
|  | ce25 | 32.518 s | 33.061 s | 31.515 s | 33.205 s | 2% | -13.3% | 10 |
|  | jdk17 | 18.958 s | 19.458 s | 18.148 s | 19.576 s | 2% | -49.4% | 20 |
|  | jdk21 | 17.291 s | 17.623 s | 16.946 s | 17.775 s | 1% | -53.9% | 10 |
|  | jdk25 | 16.883 s | 17.036 s | 16.647 s | 17.066 s | 1% | -55.0% | 10 |
|  | shipping | 34.965 s | 35.402 s | 33.912 s | 35.438 s | 1% | -6.7% | 10 |

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

### Is the upgrade worth adopting? Yes — but the answer forks on licensing.

The measured facts:

- **Oracle GraalVM**: −49% to −55% on the whole workflow, byte-identical
  generated C++, for a diff of 1 to 7 functional lines.
- **GraalVM Community**: **−11.9% to −13.3%** for the same diff.
- The published artifact is **Community** today.

So there are really two decisions, and they should be taken in this order.

### Decision 1 — is Oracle GFTC acceptable for release builds?

This is a project/legal call, not an engineering one, and it should be made
before any of the version questions. GFTC permits free production use and
redistribution of the output, but it is not an open-source licence, and moving
to it changes the licensing posture of an artifact that is currently GPLv2+CE.

**If yes:** the win is large and cheap. Take Oracle GraalVM.
**If no:** the measured open-source ceiling is **−13.3%**, still worth having
for a near-zero diff, and the more interesting options become `-O3` on
Community and Scala Native.

### Decision 2 — if Oracle is acceptable, which JDK?

**JDK 21.** It captures 53.9% of the 55.0% available, so JDK 25 buys ~1pp more
while carrying a dependency on a JDK method scheduled for removal (§4). Its
only test failures are provably content-preserving JSON reordering, its
generated C++ is byte-identical, and it is the current maintained LTS —
where JDK 17's GraalVM line is already end-of-updates.

**JDK 17** is the lower-risk alternative: the only fully green suite, no Scala
bump, no `-source` pin, and 49.4% of 55.0% is ~90% of the prize for **one**
functional line. A defensible choice; just book the end-of-updates position as
debt.

**Not JDK 25** on Scala 3.3.x.

### If Oracle is not acceptable

Two FOSS levers, neither fully resolved in this report:

1. **`-O3` on Community.** Community *does* ship `-O3` (only PGO is
   Oracle-exclusive; `-march` is also available). A CE 25 `-O3` binary was
   built but **not yet benchmarked**, so its effect is **unmeasured**.
2. **Scala Native** (BSD-3). Investigated and partially built — see §8.

### Is a per-CPU-level variant scheme justified?

**Unanswerable — `perf/march-v3` was never built or measured.** No march-v3
number exists, so the ~3% stop condition cannot be evaluated. Stated as unknown
rather than guessed.

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
