pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // io.livekit:livekit-android pulls com.github.davidliu:audioswitch from JitPack.
        maven { url = uri("https://jitpack.io") }
    }
}
rootProject.name = "nexora-livekit"
