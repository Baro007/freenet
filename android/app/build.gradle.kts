import java.net.URLClassLoader
import java.net.URL

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.freenet.vpn"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.freenet.vpn"
        minSdk = 26 // Required for Android VpnService & Modern APIs
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
        ndk {
            // arm64-v8a for physical devices and arm64 Mac emulators
            abiFilters.addAll(listOf("arm64-v8a"))
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.11" // Compatible with Kotlin 1.9.23
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    
    // Compose
    implementation(platform("androidx.compose:compose-bom:2024.02.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    
    // sing-box Core Wrapper from Maven Central
    implementation("net.clever-vpn:libbox-android:2.1.1")
}

tasks.register("printPlatformInterface") {
    doLast {
        val configuration = configurations.getByName("debugCompileClasspath")
        val files = configuration.resolve()
        val urls = files.flatMap { file ->
            if (file.extension == "aar") {
                val tempDir = File(project.layout.buildDirectory.asFile.get(), "tmp/extract-${file.nameWithoutExtension}")
                tempDir.deleteRecursively()
                tempDir.mkdirs()
                copy {
                    from(zipTree(file))
                    into(tempDir)
                }
                val classesJar = File(tempDir, "classes.jar")
                if (classesJar.exists()) listOf(classesJar.toURI().toURL()) else emptyList()
            } else if (file.extension == "jar") {
                listOf(file.toURI().toURL())
            } else {
                emptyList()
            }
        }.toTypedArray()

        val classLoader = URLClassLoader(urls, project.buildscript.classLoader)
        try {
            val platformInterfaceClass = classLoader.loadClass("io.nekohasekai.libbox.PlatformInterface")
            println("=== io.nekohasekai.libbox.PlatformInterface Methods ===")
            for (method in platformInterfaceClass.getDeclaredMethods()) {
                val retName = method.getReturnType().getName()
                val mName = method.getName()
                val params = method.getParameterTypes().map { it.getName() }.joinToString(", ")
                println("$retName $mName($params)")
            }
        } catch (e: Exception) {
            println("Error loading PlatformInterface: ${e.message}")
            e.printStackTrace()
        }
        
        try {
            val commandServerClass = classLoader.loadClass("io.nekohasekai.libbox.CommandServer")
            println("=== io.nekohasekai.libbox.CommandServer Methods ===")
            for (method in commandServerClass.getDeclaredMethods()) {
                val retName = method.getReturnType().getName()
                val mName = method.getName()
                val params = method.getParameterTypes().map { it.getName() }.joinToString(", ")
                println("$retName $mName($params)")
            }
        } catch (e: Exception) {
            println("Error loading CommandServer: ${e.message}")
        }

        try {
            val commandServerHandlerClass = classLoader.loadClass("io.nekohasekai.libbox.CommandServerHandler")
            println("=== io.nekohasekai.libbox.CommandServerHandler Methods ===")
            for (method in commandServerHandlerClass.getDeclaredMethods()) {
                val retName = method.getReturnType().getName()
                val mName = method.getName()
                val params = method.getParameterTypes().map { it.getName() }.joinToString(", ")
                println("$retName $mName($params)")
            }
        } catch (e: Exception) {
            println("Error loading CommandServerHandler: ${e.message}")
        }

        try {
            val overrideOptionsClass = classLoader.loadClass("io.nekohasekai.libbox.OverrideOptions")
            println("=== io.nekohasekai.libbox.OverrideOptions Methods ===")
            for (method in overrideOptionsClass.getDeclaredMethods()) {
                val retName = method.getReturnType().getName()
                val mName = method.getName()
                val params = method.getParameterTypes().map { it.getName() }.joinToString(", ")
                println("$retName $mName($params)")
            }
        } catch (e: Exception) {
            println("Error loading OverrideOptions: ${e.message}")
        }

        try {
            val stringIteratorClass = classLoader.loadClass("io.nekohasekai.libbox.StringIterator")
            println("=== io.nekohasekai.libbox.StringIterator Methods ===")
            for (method in stringIteratorClass.getDeclaredMethods()) {
                val retName = method.getReturnType().getName()
                val mName = method.getName()
                val params = method.getParameterTypes().map { it.getName() }.joinToString(", ")
                println("$retName $mName($params)")
            }
        } catch (e: Exception) {
            println("Error loading StringIterator: ${e.message}")
        }

        try {
            val connectionOwnerClass = classLoader.loadClass("io.nekohasekai.libbox.ConnectionOwner")
            println("=== io.nekohasekai.libbox.ConnectionOwner Methods and Constructors ===")
            for (constructor in connectionOwnerClass.getDeclaredConstructors()) {
                println("Constructor: $constructor")
            }
            for (method in connectionOwnerClass.getDeclaredMethods()) {
                val retName = method.getReturnType().getName()
                val mName = method.getName()
                val params = method.getParameterTypes().map { it.getName() }.joinToString(", ")
                println("$retName $mName($params)")
            }
        } catch (e: Exception) {
            println("Error loading ConnectionOwner: ${e.message}")
        }

        try {
            val tunOptionsClass = classLoader.loadClass("io.nekohasekai.libbox.TunOptions")
            println("=== io.nekohasekai.libbox.TunOptions Methods ===")
            for (method in tunOptionsClass.getDeclaredMethods()) {
                val retName = method.getReturnType().getName()
                val mName = method.getName()
                val params = method.getParameterTypes().map { it.getName() }.joinToString(", ")
                println("$retName $mName($params)")
            }
        } catch (e: Exception) {
            println("Error loading TunOptions: ${e.message}")
        }
    }
}




