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

subprojects {
    fun forceCompileSdk(p: Project) {
        val ext = p.extensions.findByName("android") ?: return
        try {
            ext.javaClass.methods
                .firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
                ?.invoke(ext, 36)
        } catch (e: Exception) {
            println("compileSdk override skipped for ${p.name}: ${e.message}")
        }
    }
    if (state.executed) forceCompileSdk(this) else afterEvaluate { forceCompileSdk(this) }
}
