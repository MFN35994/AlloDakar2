allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication {
                create<BasicAuthentication>("basic")
            }
            credentials {
                username = "mapbox"
                password = "sk.eyJ1IjoidHJhbnNlbiIsImEiOiJjbXA5eGdjcGcwejQ3MnRzZXFkeGx4dDV2In0.FUT3_Ruc7bsNdK9QpcUtUw"
            }
        }
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
    extra["MAPBOX_DOWNLOADS_TOKEN"] = "sk.eyJ1IjoidHJhbnNlbiIsImEiOiJjbXA5eGdjcGcwejQ3MnRzZXFkeGx4dDV2In0.FUT3_Ruc7bsNdK9QpcUtUw"
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    configurations.all {
        resolutionStrategy {
            force("androidx.browser:browser:1.8.0")
            force("androidx.core:core:1.13.1")
            force("androidx.core:core-ktx:1.13.1")
        }
    }
}

subprojects {
    val configureSubproject = {
        val isAndroid = plugins.hasPlugin("com.android.application") || 
                        plugins.hasPlugin("com.android.library")
        
        if (isAndroid) {
            val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
            
            if (android != null && android.namespace.isNullOrEmpty()) {
                android.namespace = project.group.toString()
            }
            
            // Fix for missing Theme_AppCompat_NoActionBar in older plugins
            dependencies.add("implementation", "androidx.appcompat:appcompat:1.6.1")
            dependencies.add("implementation", "com.google.android.material:material:1.9.0")
        }
    }
    
    if (state.executed) {
        configureSubproject()
    } else {
        afterEvaluate {
            configureSubproject()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
