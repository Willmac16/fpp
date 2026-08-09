# FPP Toolchain Upgrade — Benchmark & Evaluation Report

## STATUS: INCOMPLETE. Read §0 before using anything here.

**Phase A (baseline) is complete and measured. Phases B and C are NOT
measured.** No performance number for any upgraded or optimized toolchain
appears in this report, because none was produced. Nothing below is estimated,
extrapolated, or inferred.

---

## 0. What was and was not done

| Brief item | Status |
|---|---|
| Phase A — baseline `./release`, env capture, benchmark | **Done, measured** |
| Phase B — build fixes for a current GraalVM/JDK | **Build fixes done and verified to compile; native image never built** |
| Phase B — regenerate reflection config | **Started, interrupted, rolled back** (see §4) |
| Phase B — acceptance (`./test`, project build, C++ diff) | **Not run against an upgraded binary** |
| Phase B — benchmark | **Not run** |
| Phase C — `perf/o3`, `perf/pgo`, `perf/march-v3` | **Not started** |
| march-v3 stop-condition decision | **Cannot be answered — no number** |

Cause: the work ran in an ephemeral cloud container which restarted partway
through Phase B, killing the in-flight reflection-tracing run and the JDK 17
native-image build. Phase A artifacts survived; Phase B/C artifacts did not.

Two further limits that would apply even to a completed run:

1. **The corpus is F´ `Ref`, not a real project.** The brief's `./project` was
   not present in this environment (`OBSTACLES.md` O-1). The brief itself warns
   Ref "is small and will understate the deltas." Any future delta measured
   with this harness is a **lower bound**.
2. **The host is a shared 4-core cloud VM.** Power/thermal state is not
   controllable (O-9). This is why the protocol reports medians and full
   distributions, never means — an early contended `fpp-depend` sample had
   σ/mean of 48% and a mean sitting 27% above its own median, purely from
   interference outliers. Re-running with nothing else on the box brought the
   same measurement to σ/median 3%.

---

## 1. Benchmark methodology (§3 of the brief)

| Protocol item | What was done |
|---|---|
| Tool | `hyperfine` 1.19.0 |
| Warmup runs | 3 (protocol minimum) |
| Measured runs | **100** for the three fpp tool measurements; **20** for cold `generate` (protocol minimum; each run costs ~14 s) |
| Statistic | Median, p95, min, max, σ/median — computed from hyperfine's full per-run export, not its summary |
| Corpus | Harvested once, reused verbatim by every phase |
| Isolation | No other build or benchmark running concurrently during any measurement |

### Corpus — harvested, not hand-rolled

`bench/prep-corpus.sh` runs a real `fprime-util generate` against the Ref
deployment and harvests the **verbatim command lines the F´ build emits** for
the deployment topology module `Ref/Top`, the largest single fpp invocation in
the build:

- `fpp-to-cpp` — 2 source files, **101** model imports via `-i`, 4 location paths via `-p`
- `fpp-depend` — the same 2 sources against an **802-directive** `locs.fpp`
- `fpp-check` — `Fw/Com/Com.fpp`, a real self-contained 11-line fprime model,
  small enough that its runtime is dominated by per-invocation startup

Only two things are rewritten in the harvested commands: the tool path (so each
phase uses its own binary) and the output directory (so measured runs never
write into, or benefit from, the F´ build cache).

### Guards against caching artifacts

- `fpp-to-cpp` and `fpp-depend` get a `--prepare` that wipes and recreates their
  output directory before **every** run.
- Cold `fprime-util generate` gets a `--prepare` that deletes the whole build
  cache and `build-artifacts` before **every** run.
- The phase's `bin` goes first on `PATH` and the harness **asserts** that
  `fpp-check` resolves there, so a measurement cannot silently fall through to
  the pip-installed `fprime-fpp` 3.3.0a15 shims in the venv.
- `fpp-check`'s measurement uses `--shell=none`; a ~2 ms shell spawn is a
  material fraction of a 14 ms startup. The other three keep the shell, where
  the same overhead is noise.

---

## 2. Results

Phase A only. **There is no Phase B or Phase C row because those phases were
never measured.** The "Δ vs baseline" column exists for the phases that were
not reached.

| Tool | Phase | Median | p95 | Min | Max | σ/median | Δ vs baseline | n |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| fpp-depend (full model) | baseline | 553.5 ms | 583.7 ms | 520.4 ms | 615.8 ms | 3% | — | 100 |
| fpp-to-cpp (full model) | baseline | 1.331 s | 1.443 s | 1.261 s | 1.568 s | 4% | — | 100 |
| fpp-check (single small file) | baseline | 14.1 ms | 15.5 ms | 13.3 ms | 16.8 ms | 5% | — | 100 |
| fprime-util generate (cold) | baseline | 13.823 s | 15.392 s | 13.100 s | 15.994 s | 5% | — | 20 |

Raw per-run distributions: `bench/results/baseline-*.json`.
Regenerate the table with `python3 bench/analyze.py bench/results baseline`.

### One observation worth carrying into Phase C

Cold `fprime-util generate` shows **20.7 s of user time against 13.8 s of wall
time** — it is parallel, and dominated by CMake configure, not by fpp. Native
`fpp-check` startup is already **14.1 ms**. Together these bound how much any
native-image optimization flag can possibly buy on measurement 3: most of that
14 s is not fpp, and per-invocation startup is already small in absolute terms.
Expect `-O3`/PGO to move measurements 1 and 2 and to be nearly invisible in 3.
This is a prediction, not a measurement, and is flagged as such.

---

## 3. Per-phase environments

### Baseline (measured)

Full capture: `bench/baseline-env.txt`. Summary:

| | |
|---|---|
| fpp SHA | `4ff84dd8646abcea618f2e3596e968a7945ee995` |
| fprime SHA | `dc115c3dc2228c403477bd7738fc6bd895a72468` |
| JDK / GraalVM | GraalVM CE **22.3.0**, OpenJDK **11.0.17** (matches `.github/actions/native-tools-setup/env-setup`) |
| Scala | 3.1.2 |
| sbt | 1.10.11 (sbt-assembly 1.2.0) |
| native-image flags | `--no-fallback --install-exit-handlers` (no `FPP_NATIVE_IMAGE_FLAGS`) |
| C compiler | gcc 13.3.0 |
| Host | Intel Xeon @ 2.80GHz, 4 cores, 15 GiB, Linux 6.18.5 |
| Binary size | 58 MB |

### JDK 21 (built as a jar; native image not built)

Oracle GraalVM **21.0.12+7.1** (LTS, 2026-07). Scala **3.3.8** with
`-source:3.1`. The jar builds and assembles cleanly; `./release` was never run
to completion, so there is **no native binary and no measurement**.

### JDK 17 (built as a jar; native image not built)

Oracle GraalVM **17.0.12+8.1**. Scala **3.1.2, unmodified**. See §5.

---

## 4. Acceptance

Per §4 of the brief, a green unit suite is not sufficient. Here is the honest
state of each criterion.

| Criterion | Baseline | Upgraded toolchain |
|---|---|---|
| 1. `./test` full suite green | **Pass** — run against the **native** binary by `./release` | **Not run** |
| 2. `fprime-util generate && fprime-util build` clean | `generate` **pass** (run 20+ times under benchmark); full `build` **not run** | **Not run** |
| 3. Generated C++ diffed vs baseline | Baseline side **captured**: 832 files from 145 `fpp-to-cpp` invocations | **No second side to diff against** |

The baseline C++ snapshot exists and the differ is ready
(`bench/gen-cpp-snapshot.sh`), so criterion 3 is one build away from being
answerable — but it **has not been answered**.

Caveat on criterion 1 even for the baseline: `lib/test/codegen/CppWriter/run`
`exit 0`s when `scalac` is absent, which it is here. That test is **skipped but
counted as passed** (O-7), so "all tests green" is slightly overstated in every
phase.

### Reflection config — started, interrupted, rolled back

The regeneration in Phase B.4 was begun (`reflect-config.json` cleared to `[]`,
`./install-trace`, `./test` under tracing). The container restarted with the
trace **23 entries** in, against a committed config of **972**.

A 23-entry config would have produced precisely the failure the brief warns
about: a native image that builds clean and dies at runtime on real models. It
was **rolled back to the committed 972-entry version**, along with the
partially-written `jni-config.json` and `resource-config.json`.

**The committed reflection config in this branch is therefore the original,
unregenerated one.** Phase B is not complete until it is regenerated — see
O-10 for why that regeneration must include `./trace-fprime`, and O-13 for why
regenerating it makes Phase B a two-variable comparison that needs care.

---

## 5. The JDK 17 question — a smaller upgrade that works

Asked mid-task: is there a JDK bump that does not require bumping Scala?
**Yes, and it was verified by building it.**

The JDK 21 failure is specific: Scala 3.1.2 cannot parse
`java.lang.reflect.AccessFlag`, which was **added in JDK 20**.

| | JDK 17 path | JDK 21 path |
|---|---|---|
| GraalVM | Oracle GraalVM 17.0.12+8.1 | Oracle GraalVM 21.0.12+7.1 |
| Scala | **3.1.2, unchanged** | 3.3.8 |
| `-source:3.1` pin | **not needed** | needed, for 60 unchecked pattern bindings |
| `.jvmopts` CMS flag removal | needed | needed |
| Total diff | **one line** | four files |
| Jar build | **verified clean** | **verified clean** |
| Native image | not built | not built |
| `-O3` / PGO / `-march` | available | available |
| Toolchain maintenance | **17.0.12 is the final GraalVM for JDK 17 — end of updates** | current maintained LTS |

Both reach the same `native-image` capability set, so both can answer the
Phase C questions. The real trade is **a one-line diff against a dead-ended
toolchain** versus **a four-file diff against a maintained one**.

My recommendation, stated as a judgement and not as a measurement: take
**JDK 21**. The Scala 3.3.8 + `-source:3.1` change is mechanical, is confined to
build configuration, touches no compiler source, and buys a toolchain that will
still receive security updates. Adopting a GraalVM line that is already
end-of-updates in order to save three lines of build config is a poor trade for
a tool that ships to other people. JDK 17 remains a legitimate fallback if the
Scala bump turns out to perturb generated C++ — which is exactly what
acceptance criterion 3 exists to detect, and which has **not yet been checked**.

---

## 6. Recommendation

### Is the upgrade worth adopting?

**Not answerable from measurement, and I will not guess.** No upgraded native
binary was built, so there is no performance evidence either way.

What *is* established:

- The upgrade is **mechanically feasible**. Both JDK 17 and JDK 21 build the
  compiler to a working jar, with build-configuration changes only and **zero
  compiler source changes**, as the brief required.
- The blockers are known, small, and enumerated (O-12): a Scala compiler bump
  (JDK 21 only), a `-source:3.1` pin (JDK 21 only), a duplicated Scala version
  pin in `compiler/install`, and a JDK-14-removed CMS flag in `.jvmopts`.
- The motivation for upgrading is real regardless of the benchmark: the current
  toolchain is pinned to **GraalVM 22.3.0 / JDK 11 from 2022**, and `-O3`, PGO
  and `-march` — the entire subject of Phase C — are **unavailable** on it.

### Is a per-CPU-level variant scheme justified?

**No number exists, so the stop condition cannot be evaluated.** `perf/march-v3`
was never built or measured.

I would not treat that as an open question deserving much optimism. The brief's
own reasoning — FPP is branchy pointer-chasing and allocation, not vectorizable
numeric code — is sound, and §2 adds a measured constraint: startup is already
14 ms and cold `generate` is dominated by CMake rather than fpp. The burden of
proof sits with march-v3 clearing 3%, and the harness is ready to test it in
about ten minutes of machine time. **Until it is run, the answer is "unknown",
not "probably yes".**

---

## 7. Reproducing / finishing this

Everything needed is committed. On a machine with `sbt`, a GraalVM, and
`hyperfine`:

```sh
# 1. baseline (already measured; artifacts in bench/results/)
export GRAALVM_JAVA_HOME=/path/to/graalvm-ce-java11-22.3.0
export FPP_JAVA_HOME="$GRAALVM_JAVA_HOME"
cd compiler && ./release

# 2. corpus — run ONCE, then reuse for every phase
bash bench/prep-corpus.sh /path/to/compiler/bin

# 3. per phase
bash bench/capture-env.sh <phase> "$GRAALVM_JAVA_HOME" "$FPP_NATIVE_IMAGE_FLAGS"
bash bench/run-bench.sh   <phase> /path/to/compiler/bin
bash bench/gen-cpp-snapshot.sh <phase> /path/to/compiler/bin

# 4. table
python3 bench/analyze.py bench/results baseline

# 5. C++ acceptance diff
diff -r /home/user/cppsnap/baseline /home/user/cppsnap/<phase>
```

Phase C flags go through `FPP_NATIVE_IMAGE_FLAGS`, which `compiler/release`
already honours: `-O3`; `--pgo-instrument` then `--pgo=<profile>.iprof`;
`-march=x86-64-v3`. **Never `-march=native`** — this build host reports AVX-512,
which would be baked into a binary shipped to machines that do not have it.
