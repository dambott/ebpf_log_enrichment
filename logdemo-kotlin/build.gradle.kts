plugins {
    kotlin("jvm") version "2.0.21"
    application
}

group = "com.ebpflogs"
version = "1.0.0"

repositories {
    mavenCentral()
}

application {
    mainClass.set("com.ebpflogs.logdemo.MainKt")
}

tasks.jar {
    manifest {
        attributes["Main-Class"] = "com.ebpflogs.logdemo.MainKt"
    }
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE
    from(configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) })
}
