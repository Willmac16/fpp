# Obstacles, Deviations, and Unverified Items

This file records everything that failed, was worked around, or was skipped.
Anything **not actually verified** is flagged explicitly.

Environment: single 4-core `Intel(R) Xeon(R) Processor @ 2.80GHz`, 15 GiB RAM,
Ubuntu 24.04 container (Linux 6.18.5). All work performed in an ephemeral
cloud container.

---

## BLOCKER-CLASS DEVIATIONS FROM THE BRIEF

### O-1. `./project` does not exist — no real F´ project corpus

The brief specifies three side-by-side repos: `./fpp`, `./fprime`, `./project`,
with `./project` being "our F´ project" and the benchmark corpus
("the largest real topology in `./project`").

**Only `./fpp` and `./fprime` were present in this environment.** There is no
`./project`, and no credential or URL was supplied that would identify it.

Per the brief's own fallback instruction, the Ref deployment is used instead,
and this is stated explicitly here and in `REPORT.md`:

> **All benchmark numbers in this report are measured against F´ `Ref`, not
> against a real project topology. The brief itself warns that "Ref is small
> and will understate the deltas." Treat every delta in the report as a
> lower bound on what a real project would show.**

### O-2. `fprime/Ref` has moved — fallback corpus is at a different path

The brief's fallback (`fprime/Ref`) does not exist at that path in current
`nasa/fprime` (SHA `dc115c3d`). The Ref deployment now lives at
`fprime/TestDeploymentsProject/Ref`. Used that.

Scale of the fallback corpus, for calibration:
- Ref deployment: 9 `.fpp` files, `Top/topology.fpp` = 183 lines, `Top/instances.fpp` = 104 lines
- Framework model pulled in as dependencies: 182 `.fpp` files under `Fw Svc Drv Os Utils CFDP`

### O-3. `./trace-fprime` no longer exists — Phase B.4 cannot be run as written

The brief's mandatory reflection-config regeneration step says:

```
export FPRIME=../../fprime && ./trace-fprime
```

`compiler/trace-fprime` **was deleted upstream** in commit `a48f94c7`
("Remove trace-fprime", Rob Bocchino, 2026-06-08), which also stripped the
corresponding section out of `compiler/README.adoc`. It is not present on our
fork's `main` either.

Consequence, and this matters for correctness: the surviving procedure
(documented in `compiler/README.adoc`) regenerates reflection config from
`./test` **only**. The tracing agent therefore observes only the reflection
performed by the compiler's own unit-test corpus, **not** the reflection
exercised by running the tools over real F´ framework models. Any reflective
path reachable only from an fprime-shaped model is no longer captured by the
documented workflow.

---

## BUILD-SYSTEM DEFECTS FOUND (pre-existing, not introduced by this work)

### O-4. `compiler/release` archive check works only by accident of word-splitting

`compiler/release` verifies the release tarball with:

```sh
if ! evalp diff -q "$native_bin/$file check-tar/$native_bin/$file"
```

Both paths sit inside **one** set of quotes, so `evalp` is handed a single
argument. It survives only because `evalp` runs its arguments unquoted:

```sh
evalp() { echo "$@"; $@; }
```

which re-splits that one argument back into two operands. Verified empirically:
`./release` exits **0**, and the log shows `diff` receiving two paths.

So this is **not** a live bug — flagged only as fragility. The check would break
the moment a path contained a space, and the surrounding `if !` would then
report `[ERROR] Archive creation failed` for a perfectly good archive. Not
fixed (toolchain-only task), but worth quoting properly at some point.

### O-5. `GRAALVM_JAVA_HOME` vs `FPP_GRAALVM_JAVA_HOME` are inconsistent

- `compiler/release` requires `GRAALVM_JAVA_HOME`
- `compiler/install-trace` requires `FPP_GRAALVM_JAVA_HOME`
- `.github/actions/native-tools-setup/env-setup` exports `FPP_GRAALVM_JAVA_HOME`

So the CI setup action does **not** satisfy `./release`. Both variables were
set to the same value throughout this work to sidestep it. Not fixed
(out of scope), but worth a one-line cleanup.

---

## WORKAROUNDS APPLIED

### O-6. `gu install native-image` fails behind the egress proxy

The baseline toolchain (GraalVM CE 22.3.0) ships `native-image` as a separate
`gu` component. `gu install native-image` fails with:

```
I/O error occurred: PKIX path building failed: ... unable to find valid certification path
```

`gu` does not honor the container's injected JVM truststore. Worked around by
downloading the component archive directly with `curl` (which does trust the
proxy CA) and installing from file:

```
curl -sSL -o ni-component.jar https://github.com/graalvm/graalvm-ce-builds/releases/download/vm-22.3.0/native-image-installable-svm-java11-linux-amd64-22.3.0.jar
gu install -L ni-component.jar
```

This is an environment artifact, not an fpp problem. The installed component is
the official 22.3.0 artifact, so the baseline is faithful.

### O-7. One unit test self-skips without Scala on PATH

`compiler/lib/test/codegen/CppWriter/run` compiles Scala source as part of the
test. When `scalac` is unavailable it prints `scalac version 2.13.1 or greater
required` and **`exit 0`** — i.e. it reports success without testing anything.

Scala is not installed in this container. **This test is therefore skipped, not
passed, in every phase of this report.** It is counted as a pass by
`compiler/test`'s pass/fail tally, which slightly overstates every "all tests
green" claim below.

### O-8. F´ CMake fpp version check must be bypassed

`cmake/autocoder/fpp.cmake` compares each fpp tool's `--help` version string
against the pinned `fprime-fpp` version (3.3.0a15 in `fprime/requirements.txt`).
A locally built fpp reports whatever `git describe --tags --always` yields — for
this clone, the bare SHA `4ff84dd8`, because the clone carries no tags — so the
check can never pass for a source build.

All `fprime-util generate` invocations therefore pass
`-DFPRIME_SKIP_TOOLS_VERSION_CHECK=ON` (no space after `-D`, or fprime-util
parses the value as a positional platform name). This is the escape hatch the F´ build
provides for exactly this case, and it is applied identically in every phase, so
it does not bias any comparison.

### O-9. Benchmark host is a shared, ephemeral cloud container

The brief requires "same machine, same power/thermal state, for every phase."
Same machine and same container: yes. **Controlled power/thermal state: no.**
This is a 4-core cloud VM with neighbours; CPU frequency and steal time are not
observable or controllable from inside the container. hyperfine's own
distribution output is the only noise estimate available, which is why p95 and
the full distribution are exported for every measurement rather than a mean.

Treat small deltas (single-digit percent) as inside the noise floor unless the
distributions are visibly separated.

---

## O-10. Reflection-config regeneration: reconstructed the deleted `trace-fprime`

Following on from O-3. Recovering `compiler/trace-fprime` from git
(`git show a48f94c7^:compiler/trace-fprime`) shows what the deleted step
actually covered:

```sh
fprime_generate_flags="-f -DFPRIME_SKIP_TOOLS_VERSION_CHECK=ON -DFPRIME_ENABLE_JSON_MODEL_GENERATION=ON --ut --make"
fprime_project_paths=". ./FppTestProject/FppTest ./Ref"
...
dependencies=`fpp-depend ../build-fprime-automatic-native-ut/locs.fpp *.fpp`
fpp-to-json ${dependencies} *.fpp
```

Two things there are **not** reachable from `compiler/test`:

- `-DFPRIME_ENABLE_JSON_MODEL_GENERATION=ON` plus the explicit `fpp-to-json`
  run. That is the circe JSON path, which is the single most
  reflection-dependent part of the compiler — precisely the code that produces
  a binary that "builds clean and fails at runtime on real models."
- Real F´ framework/topology models, as opposed to the compiler's own test
  fixtures.

Clearing `reflect-config.json` and regenerating from `./test` alone would
therefore have *reduced* reflection coverage relative to the config already
committed. Rather than accept that regression, the trace step was reconstructed
against the current fprime layout (`./Ref` no longer exists; the deployment is
now `./TestDeploymentsProject/Ref` — see O-2), and the regenerated config was
diffed against the previous one.

The old script also would not run as-is today: it activates a venv with
`. /tmp/fprime-venv` (missing `/bin/activate`) and points at the pre-move `./Ref`
path. That is plausibly why it was deleted rather than maintained.

Outcome of the diff is recorded in `REPORT.md` §4.

### Why the JSON path dominates: measured breakdown of `reflect-config.json`

The claim above is not qualitative. Bucketing the committed 972-entry
`reflect-config.json` by class name:

| Bucket | Entries |
|---|---:|
| `fpp.compiler.codegen.AnalysisJsonEncoder$$anon$N` | 607 |
| `fpp.compiler.codegen.AstJsonEncoder$$anon$N` | 339 |
| `fpp.compiler.codegen.LocMapJsonEncoder$$anon$N` | 1 |
| `fpp.compiler.*` (everything else) | 10 |
| `scala.*` / `java.*` / other | 14 |
| `io.circe.*` itself | 1 |

**947 of 972 entries — 97% — name circe-derived JSON encoder classes.** `circe-generic`
derives an encoder per type and each compiles to an anonymous class. They are
fpp's own derived classes rather than circe's: only one `io.circe` name appears.

**What is actually being reflected on is not circe.** Inspecting the registered
members rather than the class names: **963 of 963 field registrations are
`0bitmap$N`**, and the only registered methods are
`java.lang.invoke.VarHandle.releaseFence` and
`SAXParserFactoryImpl.<init>`. `0bitmap$N` fields are **Scala 3 lazy-val
bitmaps** — on the JVM, `scala.runtime.LazyVals` resolves them with
`Unsafe.objectFieldOffset(getDeclaredField(...))`, and that is the reflection
the agent traces. circe on Scala 3 derives at *compile* time; each derived
encoder just happens to hold a lazy val.

So the correct statement is: the config is a registry of lazy-val bitmaps inside
circe-derived classes, not a registry of circe runtime reflection. The
operational conclusion is unchanged, because those encoder classes are only
instantiated when the JSON path actually runs.

`native-image` closes the world and drops anything unregistered. Those ~946 anon
classes span the full AST/Analysis type graph. `compiler/test` does exercise the
path, but with **2 `fpp-to-json` test directories and 1 `fpp-to-dict`, out of 102
total**, over small fixture models — so it reaches only the encoders those
fixtures instantiate.

That is the size of the hole: regenerating from `./test` alone plausibly
recovers a few dozen of ~946. The image links, the suite goes green, and
`fpp-to-dict` on a real topology then hits an unregistered encoder at runtime.

### O-11. `JAVA_TOOL_OPTIONS` breaks the JVM-tool test suite in this container

The container sets `JAVA_TOOL_OPTIONS` (proxy truststore + proxy host) globally.
Every JVM started with it prints to **stderr**:

```
Picked up JAVA_TOOL_OPTIONS: -Djavax.net.ssl.trustStore=...
```

`compiler/test`'s per-test scripts capture `2>&1` into `*.out.txt` and diff
against a checked-in `*.ref.txt`, so that banner lands in the actual output and
**every JVM-tool test fails** — 89 failures before the run was stopped.

This is an environment artifact, not an fpp or toolchain defect. Two things made
it easy to misread:

- Phase A's `./test` passed cleanly, because it ran **native** binaries, which
  do not read `JAVA_TOOL_OPTIONS`. Only the tracing step runs the JVM tools.
- A stray `.lock` file was present in the merge dir at the same time, which is
  the documented cause of "tests go haywire" — a plausible but, here, wrong
  explanation. Checking an actual `*.diff.txt` showed the real cause was the
  banner, not the lock.

Resolution: `install-trace` keeps `JAVA_TOOL_OPTIONS` (sbt needs the proxy
truststore to resolve dependencies), and `./test` runs under
`env -u JAVA_TOOL_OPTIONS`. Nothing in the repository was changed for this.

---

## BUILD CHANGES REQUIRED BY THE UPGRADE

### O-12. JDK 21 forces a Scala compiler bump — handled without touching sources

Building the unmodified tree on JDK 21 fails immediately:

```
[error] error while loading AccessFlag,
[error] class file /modules/java.base/java/lang/reflect/AccessFlag.class is broken, reading aborted
[error] bad constant pool index: 0 at pos: 5189
```

`java.lang.reflect.AccessFlag` was added in **JDK 20**. Scala 3.1.2 (2022)
cannot parse it. The Scala compiler must move to a version that understands
JDK 21 class files; 3.3.x is the LTS line, so `3.3.8`.

That bump then surfaces a *second*, independent problem: Scala 3.2 made
unchecked pattern bindings a hard error, and the compiler sources contain **60**
of them, all of the shape

```scala
val hd :: tl = someList          // pattern type ::[A] is more specialized than List[A]
```

The brief forbids compiler source changes. Both problems are therefore solved
in build configuration only:

| Change | File | Why |
|---|---|---|
| `scalaVersion` 3.1.2 → 3.3.8 | `compiler/build.sbt` | JDK 21 class files |
| `scala_version` 3.1.2 → 3.3.8 | `compiler/install` | locates `target/scala-<ver>` assembly jar; **duplicated pin, must stay in sync with build.sbt** |
| add `-source:3.1` | `compiler/build.sbt` | keeps 3.1 language semantics so the 60 pattern bindings still compile |
| drop `-XX:+CMSClassUnloadingEnabled` | `compiler/.jvmopts` | CMS was **removed in JDK 14**; the flag makes a JDK 21 JVM refuse to start |

**Not verified / follow-up:** `-source:3.1` is a deliberate hold, not a fix. The
right follow-up is `sbt -rewrite -source 3.2-migration` to migrate those 60
bindings and then drop the flag — but that *is* a compiler source change and is
explicitly out of scope for this task.

### O-13. Phase B changes two variables at once: toolchain **and** reflection config

The brief requires "one variable per branch", and separately requires that
Phase B regenerate `reflect-config.json`. Those two requirements conflict:
regenerating the reflection config changes the set of classes reachable in the
native image, which can move both binary size and startup time on its own.

So a naive Phase A vs Phase B comparison would be measuring
`JDK 11 -> JDK 21` *plus* `committed reflect-config -> regenerated
reflect-config`, with no way to attribute a delta to either.

How this is handled:

- The **JDK 17 phase** carries the *committed* 972-entry `reflect-config.json`
  unchanged, so `baseline -> jdk17` isolates the toolchain variable cleanly.
- The **JDK 21 phase** carries the regenerated config, as the brief mandates.
- The regenerated config is diffed against the committed one and the entry
  counts are reported, so any confound is at least visible and bounded.

This is called out rather than silently averaged away.

---

## O-14. Container restart ended the run; Phases B and C were not measured

The work ran in an ephemeral cloud container which restarted during Phase B.
Killed in flight:

- the reflection-tracing `./test` run (23 of an eventual ~972 entries written)
- the JDK 17 `native-image` build (died at stage 5/8)

Survived: all Phase A artifacts, the benchmark harness and corpus, the 832-file
baseline C++ snapshot, and every build-configuration change.

**Explicitly not verified as a result — do not read anything into their absence:**

- no native binary for JDK 21 or JDK 17 (only jars, which do build cleanly)
- no Phase B benchmark, and therefore no toolchain delta of any kind
- no Phase C at all: `perf/o3`, `perf/pgo`, `perf/march-v3` were never created,
  built, or measured
- **no march-v3 number, so the ~3% stop condition cannot be evaluated**
- no acceptance run against an upgraded binary: `./test`, `fprime-util build`,
  and the generated-C++ diff all have a baseline side only
- no regenerated reflection config (rolled back — see below)

### Rollback of the partial reflection config

The interrupted trace left `reflect-config.json` at 23 entries versus the
committed 972, plus partially-written `jni-config.json` and
`resource-config.json`. Committing those would have produced exactly the
failure mode the brief calls out — a native image that builds clean and then
fails at runtime on real models.

All three were restored with `git checkout`. **The reflection config on this
branch is the original committed one, not a regenerated one.** Phase B remains
incomplete until it is regenerated per O-10.

---

## O-15. JDK 21 reorders dictionary JSON (3 test failures, content identical)

The Scala 3.1.2 -> 3.3.8 bump that JDK 21 requires changes the iteration order
of `typeDefinitions` in `fpp-to-dict` output. Three tests in
`tools/fpp-to-dict/test/top` fail as a result.

Parsed as JSON rather than diffed as text, the two sides are the same multiset:

```
[typeDefinitions] ref=22 out=22  same-as-multiset=True
  missing from out: 0   extra in out: 0
```

Pure reordering — nothing added, lost, or altered. A raw text diff makes it look
worse than it is (values appear to change because the diff re-aligns after a
move), which is why it was checked structurally.

Impact: breaks golden files, and makes dictionary output non-reproducible across
Scala versions. Not fixed — imposing a deterministic sort in the dictionary
writer is a compiler source change, out of scope.

## O-16. JDK 25 emits a deprecation banner on every invocation (907 failures)

Every fpp invocation under Oracle GraalVM 25.0.4 prints to **stderr**:

```
WARNING: sun.misc.Unsafe::objectFieldOffset has been called by scala.runtime.LazyVals$
WARNING: sun.misc.Unsafe::objectFieldOffset will be removed in a future release
```

`compiler/test` captures stderr into its golden-file diffs, so 907 of 1521
tests fail. Stripping `WARNING:` lines, **60 of 60 sampled outputs match their
reference exactly** — the failures are entirely the banner, not behaviour. Same
class of problem as O-11.

The second line is the real finding and is **not** cosmetic: Scala 3.3.8's
lazy-val implementation depends on a JDK method scheduled for removal. That is
the same `LazyVals` / `0bitmap$N` mechanism documented in O-10. JDK 25 on
Scala 3.3 LTS works today and breaks on a future JDK; escaping it needs a newer
Scala line (3.8.x) with `VarHandle`-based lazy vals.

**Not verified:** whether the banner can be suppressed at native-image build
time, and whether Scala 3.8.x builds fpp at all.

## O-17. Phase C was never started

`perf/o3`, `perf/pgo`, and `perf/march-v3` were not created, built, or measured.
Work was redirected to the JDK ladder (17 / 21 / 25) at the user's request.

**There is no march-v3 number, so the ~3% stop condition cannot be evaluated.**
This is stated as unknown rather than guessed. The harness is ready; each
variant is a `FPP_NATIVE_IMAGE_FLAGS` setting plus one `./release` and one
benchmark run.

---

## O-18. The toolchain upgrade silently narrows the shipped CPU baseline

Found while running Phase C, and not something the brief anticipated.

GraalVM CE 22.3.0 (baseline, and what fpp publishes today) has **no `-march`
flag at all** — `native-image --help` contains zero matches — and reports no
target machine. Every modern GraalVM, **Oracle and Community alike**, defaults
to `target machine: x86-64-v3`.

`x86-64-v3` *requires* AVX2, BMI1/2, FMA and LZCNT. Confirmed by disassembly
rather than by reading the flag:

| Binary | `-march` passed | AVX2/FMA-class instructions |
|---|---|---:|
| baseline (CE 22.3.0) | flag does not exist | **0** |
| jdk21 (Oracle 21) | **none** | **87** |
| marchv3 (Oracle 21) | `-march=x86-64-v3` | **87** |

Two consequences:

1. **`perf/march-v3` is a no-op.** It produces the same instruction set as the
   default build because the default already *is* x86-64-v3. The brief's
   "is a per-CPU-level variant scheme justified?" question is therefore moot as
   posed — there is no variant to opt into, only one to opt *out* of.
2. **Upgrading silently drops support for pre-2013 CPUs.** Anything older than
   roughly Haswell / Excavator will fault on the upgraded binary but runs the
   currently-published one. For a compiler shipped to third parties — some of
   whom run old ground-support hardware — that is a real, unrequested
   compatibility regression buried inside a "just bump the toolchain" change.

The useful variant is therefore the inverse of the brief's: `-march=compatibility`,
to restore the old baseline, with the performance cost measured. That build is
included in Phase C.

**Not verified:** that an upgraded binary actually faults on a pre-AVX2 CPU.
No such CPU was available; the claim rests on the declared target level and the
disassembly above, which is strong but indirect.

## O-19. The Oracle/Community gap is ML-inferred PGO

The `native-image` build banner differs between editions in exactly one field:

```
Oracle 21   Graal compiler: optimization level: 2, target machine: x86-64-v3, PGO: ML-inferred
CE 25       Graal compiler: optimization level: 2, target machine: x86-64-v3
CE 21       Graal compiler: optimization level: 2, target machine: x86-64-v3
```

Same optimization level, same target machine. Oracle additionally applies an
**ML-inferred profile by default**; Community does not, and cannot — `--pgo` is
absent from Community entirely.

That is a mechanistic explanation for the ~2x edition gap measured in
REPORT.md, and it explains why `-O3` on Community changed nothing (O-17 area):
the missing ingredient is profile guidance, not optimization level.
