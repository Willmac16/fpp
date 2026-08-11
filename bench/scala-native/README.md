# Scala Native — experiment record

Reference material from an attempt to build fpp with **Scala Native** instead
of GraalVM `native-image`. Motivation: the ~50% build-time win measured in
`../REPORT.md` requires **Oracle** GraalVM (GFTC). GraalVM Community — which is
what fpp actually publishes — delivers only −13.3%. Scala Native is BSD-3, so
it is the FOSS route to closing that gap.

**Nothing here is applied to the build.** These files are a record so the work
is not lost; the shipped `compiler/build.sbt` is untouched.

## How far it got

| Step | Result |
|---|---|
| Dependency resolution | **OK** — all five resolve at fpp's *exact* pinned versions via `%%%` |
| Scala version | **OK** — `nscplugin_3.1.2` exists, **no Scala bump needed** |
| `lib` compile (256 sources) | **OK, unmodified** |
| `tools/fpp` compile (14 sources) | **OK** |
| Whole-program reachability | **OK** — 10,091 classes / 69,822 methods |
| Optimizer (release-fast) | **OK** — 31 s |
| LLVM IR generation | **OK** — 21 s, "Produced 1 files" |
| Clang codegen | **very slow** — >25 min on one translation unit |
| Working binary | **not confirmed in this session** |
| Runtime performance | **NEVER MEASURED** |

## The whole diff to reach a linked binary

~62 functional lines, of which **8 touch compiler source**:

| File | Functional lines |
|---|---:|
| `build.sbt` (see `build.sbt` here) | 51 |
| `project/plugins.sbt` (new) | 1 |
| `project/assembly.sbt` (deleted) | 1 |
| `.jvmopts` (CMS removal, same as every path) | 1 |
| `tools/fpp/.../fpp-from-xml.scala` (see `fpp-from-xml.patch`) | **8** |

### The one source change

`scala.xml.XML.loadFile` was the **only** link failure in the entire compiler —
9 missing definitions, all `javax.xml.parsers.SAXParser*` / `org.xml.sax.*`,
which Scala Native's javalib does not implement. Replaced with
`scala.xml.parsing.ConstructingParser`, which is pure Scala and present in the
`_native0.4_3` artifact, plus `withLinkStubs(true)` for an external-DTD branch
that reaches `java.net.URL` (a `@stub` in SN's javalib) and is unreachable at
runtime for fpp.

Contrary to an earlier desk assessment, **`java.time.Year` linked fine** and
needed no substitute.

## Why the small diff is misleading

That 62 lines gets a *linked binary*. It is roughly half the real work. Not
done, and not in that diff:

1. **`compiler/install` is broken by it.** It finds the artifact with
   `find tools/fpp -name "*assembly*.jar"`. Scala Native produces no jar.
2. **`compiler/release` still calls `native-image`** — needs rewriting around
   `nativeLink`.
3. **The published wheel ships two artifacts**: a native `fpp` (58 MB) *and*
   `fpp.jar` (31 MB) as a JVM fallback. **Scala Native cannot produce a jar.**
   Preserving that fallback requires an `sbt-crossproject` JVM+Native
   restructure. This is the largest hidden cost and it is architectural, not a
   line count.
4. **ScalaTest was dropped** from the dependency list to get linking, so
   `sbt test` does not work in this configuration. ScalaTest-on-Native is
   unverified.
5. `compiler/test` populates `bin/` from the jar path and would need rewiring.

## Costs observed, independent of runtime speed

- **Build time**: GraalVM CE builds fpp in ~2.5 min. Scala Native spent >25 min
  in Clang alone, on a single 69,822-method translation unit. For a tool CI
  rebuilds, that is a standing cost.
- **Semantic risk**: `ConstructingParser` does no DTD/entity resolution and
  handles whitespace differently from the SAX-backed loader, so `fpp-from-xml`
  would need revalidation against real F´ XML before shipping.

## Verdict

Technically more viable than expected — it compiles, it links, and it needs no
Scala bump and only one source change. But **the payoff is entirely unmeasured**,
and the packaging story (dual native+jar distribution) is a real project rather
than a patch. Do not adopt on the strength of this record; it establishes
feasibility, not benefit.

## Reproducing

```sh
git clone <fpp> fpp-sn && cd fpp-sn/compiler
cp <this dir>/plugins.sbt project/plugins.sbt
rm project/assembly.sbt
cp <this dir>/build.sbt build.sbt
git apply <this dir>/fpp-from-xml.patch
printf -- '-Xss2M\n' > .jvmopts
sbt "lib/compile"        # ~100 s
sbt "fpp/nativeLink"     # reachability ~8 s, then a very long clang
```

Requires `clang` and `libunwind` (both present on Ubuntu 24.04 by default).
