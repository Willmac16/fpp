import scala.scalanative.build._

name := "fpp-compiler"
ThisBuild / organization := "gov.nasa.jpl"
ThisBuild / scalaVersion := "3.1.2"
ThisBuild / dependencyOverrides +=
  "org.scala-lang" %% "scala3-library" % "3.1.2"

lazy val commonScalac = Seq(
  scalacOptions ++= Seq("-deprecation", "-unchecked", "-Xmax-inlines:100")
)

lazy val nativeDeps = Def.setting(Seq(
  "com.github.scopt" %%% "scopt" % "4.0.1",
  "io.circe" %%% "circe-core" % "0.14.3",
  "io.circe" %%% "circe-generic" % "0.14.3",
  "io.circe" %%% "circe-parser" % "0.14.3",
  "org.scala-lang.modules" %%% "scala-xml" % "2.1.0"
))

lazy val root = (project in file("."))
  .settings(commonScalac)
  .aggregate(lib, fpp)

lazy val lib = project
  .enablePlugins(ScalaNativePlugin)
  .settings(commonScalac)
  .settings(libraryDependencies ++= nativeDeps.value)
  .settings(
    libraryDependencies +=
      "org.scala-lang.modules" %%% "scala-parser-combinators" % "2.1.1"
  )

lazy val fpp = (project in file("tools/fpp"))
  .enablePlugins(ScalaNativePlugin)
  .settings(commonScalac)
  .settings(libraryDependencies ++= nativeDeps.value)
  .settings(
    nativeConfig ~= { config =>
      config.withLTO(LTO.none).withMode(Mode.releaseFast).withGC(GC.immix)
        .withLinkStubs(true)
    }
  )
  .dependsOn(lib)
