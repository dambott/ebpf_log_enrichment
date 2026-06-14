name := "logdemo-scala"
version := "1.0.0"
scalaVersion := "2.13.14"

Compile / mainClass := Some("com.ebpflogs.logdemo.Main")

assembly / assemblyJarName := "logdemo-scala.jar"
assembly / mainClass := Some("com.ebpflogs.logdemo.Main")
assembly / assemblyMergeStrategy := {
  case PathList("META-INF", xs @ _*) => MergeStrategy.discard
  case _ => MergeStrategy.first
}

enablePlugins(AssemblyPlugin)
