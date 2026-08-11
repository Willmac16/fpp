// Scala Native experiment. Replaces the GraalVM native-image path with
// scala-native, which is BSD-3 (fully FOSS) rather than Oracle GFTC.
import scala.scalanative.build._

name := "fpp-compiler"
ThisBuild / organization := "gov.nasa.jpl"
ThisBuild / scalaVersion := "3.1.2"

lazy val commonScalac = Seq(
  scalacOptions ++= Seq("-deprecation", "-unchecked", "-Xmax-inlines:100")
)

// %%% must be used inside a project that has ScalaNativePlugin enabled; it
// resolves the _native0.4_3 artifacts. All are cross-published at the exact
// versions already pinned, so no dependency bumps are required.
lazy val nativeDeps = Def.setting(Seq(
  "com.github.scopt" %%% "scopt" % "4.0.1",
  "io.circe" %%% "circe-core" % "0.14.3",
  "io.circe" %%% "circe-generic" % "0.14.3",
  "io.circe" %%% "circe-parser" % "0.14.3",
  "org.scala-lang.modules" %%% "scala-parser-combinators" % "2.1.1",
  "org.scala-lang.modules" %%% "scala-xml" % "2.1.0"
))

lazy val root = (project in file("."))
  .settings(commonScalac)
  .aggregate(lib, fpp)

lazy val lib = project
  .enablePlugins(ScalaNativePlugin)
  .settings(commonScalac)
  .settings(libraryDependencies ++= nativeDeps.value)

lazy val fpp = (project in file("tools/fpp"))
  .enablePlugins(ScalaNativePlugin)
  .settings(commonScalac)
  .settings(libraryDependencies ++= nativeDeps.value)
  .settings(
    nativeConfig ~= { c =>
      // linkStubs: scala-xml's ConstructingParser has an external-DTD branch
      // that reaches java.net.URL, which is a @stub in Scala Native's javalib.
      // fpp never resolves external DTDs, so the branch is unreachable at
      // runtime; stubbing lets it link.
      c.withLTO(LTO.none).withMode(Mode.releaseFast).withGC(GC.immix)
       .withLinkStubs(true)
    }
  )
  .dependsOn(lib)
