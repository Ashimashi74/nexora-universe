NexoraLiveKit AAR goes here: `nexora-livekit-release.aar` (built from `plugin_src/livekit`).
CI builds and copies it automatically; it is git-ignored. The export plugin in
`addons/nexora_livekit/` adds it (plus the LiveKit maven dependencies) to Gradle Android exports.
