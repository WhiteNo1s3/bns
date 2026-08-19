allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// THE PLUGIN THAT AIMED TOO LOW (2026-08-19). whisper_ggml pins its own
// library module to compileSdk 34, while the ffmpeg-kit it carries demands
// 35+ — the build died on a mismatch inside someone else's package. Raising
// every library module that sits below the app's level keeps the fix in our
// tree instead of a forked dependency. Reflection, not a typed cast: the
// Android extension's shape moves between AGP majors, this does not. And
// the block above already forced :app to evaluate, so a project that is
// past its evaluation is raised on the spot — afterEvaluate would throw.
subprojects {
    val raiseCompileSdk = {
        val android = extensions.findByName("android")
        val get = android?.javaClass?.methods?.firstOrNull {
            it.name == "getCompileSdk" && it.parameterCount == 0
        }
        val set = android?.javaClass?.methods?.firstOrNull {
            it.name == "setCompileSdk" && it.parameterCount == 1
        }
        val current = if (get != null && set != null) get.invoke(android) as? Int else null
        if (current != null && current in 1..35) set!!.invoke(android, 36)
        Unit
    }
    if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
}
