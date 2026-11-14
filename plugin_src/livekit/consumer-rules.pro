# Keep the Godot plugin entry point (instantiated reflectively from the manifest meta-data).
-keep class com.nexora.livekit.** { *; }
# LiveKit / WebRTC use JNI + reflection.
-keep class io.livekit.** { *; }
-keep class livekit.org.** { *; }
-dontwarn livekit.org.jni_zero.**
-keep class org.webrtc.** { *; }
