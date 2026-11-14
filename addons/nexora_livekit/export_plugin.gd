@tool
extends EditorExportPlugin
## Godot 4.2+ "v2" Android plugin packaging for NexoraLiveKit.
## - ships the plugin AAR built from plugin_src/livekit (CI copies it into AAR_DIR)
## - declares the maven dependencies the AAR needs (a local AAR carries no POM)
## - adds JitPack, where io.livekit:livekit-android resolves com.github.davidliu:audioswitch
## Requires "Use Gradle Build" in the Android export preset.

const PLUGIN_NAME := "NexoraLiveKit"
const AAR_DIR := "res://android/plugins/nexora_livekit/"
const AAR_RELEASE := AAR_DIR + "nexora-livekit-release.aar"
const AAR_DEBUG := AAR_DIR + "nexora-livekit-debug.aar"

# Keep in sync with plugin_src/livekit/build.gradle.kts.
const LIVEKIT_VERSION := "2.30.0"
const COROUTINES_VERSION := "1.9.0"
const DEPENDENCIES: PackedStringArray = [
	"io.livekit:livekit-android:" + LIVEKIT_VERSION,
	"org.jetbrains.kotlinx:kotlinx-coroutines-android:" + COROUTINES_VERSION,
]
const MAVEN_REPOS: PackedStringArray = ["https://jitpack.io"]


func _get_name() -> String:
	return PLUGIN_NAME


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _aar(debug: bool) -> String:
	# A debug AAR is optional; the release AAR works for both variants.
	if debug and FileAccess.file_exists(AAR_DEBUG):
		return AAR_DEBUG
	return AAR_RELEASE


func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
	var path := _aar(debug)
	if not FileAccess.file_exists(path):
		push_warning("NexoraLiveKit: %s is missing — build plugin_src/livekit (gradle assembleRelease) and copy the AAR there. Voice chat will be unavailable." % path)
		return PackedStringArray()
	return PackedStringArray([path])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if not FileAccess.file_exists(_aar(_debug)):
		return PackedStringArray()
	return DEPENDENCIES


func _get_android_dependencies_maven_repos(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	return MAVEN_REPOS


# LiveKit's AAR declares permissions for camera + screen-share (foreground service) + bluetooth. NEXORA is voice-only and
# never starts a foreground service, so strip them (and notifications) from the merged manifest. The mic
# (RECORD_AUDIO) is requested only when the user joins voice (src/net/voice.gd); nothing is requested at launch.
const REMOVED_PERMISSIONS: PackedStringArray = [
	"android.permission.CAMERA",
	"android.permission.FOREGROUND_SERVICE",
	"android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION",
	"android.permission.FOREGROUND_SERVICE_MICROPHONE",
	"android.permission.POST_NOTIFICATIONS",
	"android.permission.SYSTEM_ALERT_WINDOW",
	# Bluetooth headset routing (AudioSwitch) is optional: BLUETOOTH_CONNECT is a runtime "nearby devices"
	# permission that makes installers (MIUI / Play Protect) flag the app; voice works over speaker/wired without it.
	"android.permission.BLUETOOTH",
	"android.permission.BLUETOOTH_ADMIN",
	"android.permission.BLUETOOTH_CONNECT",
	"android.permission.BLUETOOTH_SCAN",
	# signature|privileged permission merged in from a library manifest: useless for a normal app and some OEM
	# installers (Xiaomi MIUI/HyperOS) refuse or flag packages that request it.
	"android.permission.DUMP",
]


func _get_android_manifest_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	var s := ""
	for perm in REMOVED_PERMISSIONS:
		s += '    <uses-permission android:name="%s" tools:node="remove" />\n' % perm
	return s


# androidx.profileinstaller (pulled in by LiveKit/androidx) adds ProfileInstallReceiver guarded by
# android:permission="android.permission.DUMP" (adb/Play baseline-profile tooling only). Some OEM installers
# (Xiaomi MIUI/HyperOS) flag packages that mention DUMP, so drop the receiver from the merged manifest;
# the app does not need it (profiles still install via Play / ART on first runs).
func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return '        <receiver android:name="androidx.profileinstaller.ProfileInstallReceiver" tools:node="remove" />\n'
