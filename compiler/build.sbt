// See https://pbassiner.github.io/blog/defining_multi-project_builds_with_sbt.html

name := "fpp-compiler"
ThisBuild / organization := "gov.nasa.jpl"
// Scala 3.3.x is the LTS line and is the lowest Scala 3 that can read JDK 21
// class files. 3.1.2 fails on JDK 21 with:
//   class file .../java/lang/reflect/AccessFlag.class is broken
// NOTE: compiler/install pins this same version to locate the assembly jar.
// Keep the two in sync.
ThisBuild / scalaVersion := "3.3.8"

lazy val settings = Seq(
  scalacOptions ++= Seq(
    "-deprecation",
    "-unchecked",
    "-Xfatal-warnings",
    "-Xmax-inlines:100",
    // Pin the *language* level while the *compiler* moves forward for JDK 21.
    //
    // Scala 3.2 made unchecked pattern bindings (`val x :: xs = someList`) a
    // hard error. The compiler sources contain ~60 of them, so building them
    // with 3.3 semantics fails. Compiling at -source:3.1 keeps the semantics
    // the code was written against, so this upgrade stays toolchain-only and
    // does not touch a single .scala file.
    //
    // FOLLOW-UP (separate change, deliberately not done here): migrate those
    // bindings — `sbt -rewrite -source 3.2-migration` does it automatically —
    // and then drop this flag.
    "-source:3.1"
  ),
  libraryDependencies ++= dependencies, 
  Test / testOptions += Tests.Argument(TestFrameworks.ScalaTest, "-oNCXELOPQRM"),
)

lazy val dependencies = Seq(
  "com.github.scopt" %% "scopt" % "4.0.1",
  "io.circe" %% "circe-core" % "0.14.3",
  "io.circe" %% "circe-generic" % "0.14.3",
  "io.circe" %% "circe-parser" % "0.14.3",
  "org.scala-lang.modules" %% "scala-parser-combinators" % "2.1.1",
  "org.scala-lang.modules" %% "scala-xml" % "2.1.0",
  "org.scalatest" %% "scalatest" % "3.2.12" % "test",
)

lazy val root = (project in file("."))
  .settings(settings)
  .aggregate(
    lib,
    fpp
  )

lazy val lib = project
  .settings(settings)

lazy val fpp = (project in file("tools/fpp"))
  .settings(settings)
  .dependsOn(lib)
  .enablePlugins(AssemblyPlugin)
