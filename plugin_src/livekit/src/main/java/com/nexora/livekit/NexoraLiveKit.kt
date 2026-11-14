// NEXORA · Godot v2 Android plugin wrapping the LiveKit Android SDK (voice only).
// Godot side: Engine.get_singleton("NexoraLiveKit") — see res://src/net/voice.gd.
//
// Methods (@UsedByGodot, called from the Godot thread; all work is hopped onto the Android main thread):
//   connect(url, token, publish)  · setMic(on) · setSpeaker(on) · disconnect()
// Signals:
//   state(String)     "connecting" | "on" | "off" | "error"
//   speakers(String)  JSON array of active speaker identities, e.g. ["uid-a","uid-b"]
//   error(String)     human/dev readable message; prefixed "mic:" when only enabling the mic failed
package com.nexora.livekit

import android.content.Context
import android.media.AudioManager
import android.util.Log
import com.twilio.audioswitch.AudioDevice
import io.livekit.android.LiveKit
import io.livekit.android.RoomOptions
import io.livekit.android.events.RoomEvent
import io.livekit.android.events.collect
import io.livekit.android.room.Room
import io.livekit.android.room.track.RemoteAudioTrack
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import org.json.JSONArray

class NexoraLiveKit(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val TAG = "NexoraLiveKit"
        const val SIG_STATE = "state"
        const val SIG_SPEAKERS = "speakers"
        const val SIG_ERROR = "error"
    }

    // Lazy: nothing (coroutines, LiveKit, WebRTC, audio) is touched until the first voice call from Godot.
    // Godot instantiates v2 plugins at app start, so the constructor must stay trivial.
    @Volatile private var scopeCreated = false
    private val scope: CoroutineScope by lazy {
        scopeCreated = true
        CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    }

    // Everything below is only touched on the Android main thread.
    private var room: Room? = null
    private var connectJob: Job? = null
    private var eventsJob: Job? = null
    private var canPublish = false
    private var speakerOn = true
    private var micOn = false
    private var savedSpeakerphone: Boolean? = null
    private var lastState = "off"

    override fun getPluginName(): String = "NexoraLiveKit"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo(SIG_STATE, String::class.java),
        SignalInfo(SIG_SPEAKERS, String::class.java),
        SignalInfo(SIG_ERROR, String::class.java),
    )

    // ---------------------------------------------------------------- Godot API

    /** Runs [block] on the plugin scope; any failure (even class-loading) becomes an "error" signal, never a crash. */
    private fun safeLaunch(what: String, block: suspend () -> Unit) {
        try {
            scope.launch {
                try {
                    block()
                } catch (c: CancellationException) {
                    throw c
                } catch (t: Throwable) {
                    Log.w(TAG, "$what failed", t)
                    safeEmit(SIG_ERROR, "$what: ${t.message}")
                    safeEmit(SIG_STATE, "error")
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "$what could not start", t)
            safeEmit(SIG_ERROR, "$what: ${t.message}")
            safeEmit(SIG_STATE, "error")
        }
    }

    private fun safeEmit(sig: String, arg: String) {
        try { emitSignal(sig, arg) } catch (t: Throwable) { Log.w(TAG, "emit $sig failed", t) }
    }

    @UsedByGodot
    fun connect(url: String, token: String, publish: Boolean) {
        safeLaunch("connect") { doConnect(url, token, publish) }
    }

    /** Alias that does not collide with Object.connect() on the GDScript side. */
    @UsedByGodot
    fun connectRoom(url: String, token: String, publish: Boolean) = connect(url, token, publish)

    @UsedByGodot
    fun setMic(on: Boolean) {
        safeLaunch("mic") { doSetMic(on) }
    }

    @UsedByGodot
    fun setSpeaker(on: Boolean) {
        safeLaunch("speaker") {
            speakerOn = on
            room?.let { applySpeaker(it) }
        }
    }

    @UsedByGodot
    fun disconnect() {
        if (!scopeCreated) { safeEmit(SIG_STATE, "off"); return }
        safeLaunch("disconnect") {
            teardown()
            emitState("off")
            emitSpeakers(emptyList())
        }
    }

    /** Alias that does not collide with Object.disconnect() on the GDScript side. */
    @UsedByGodot
    fun disconnectRoom() = disconnect()

    // ---------------------------------------------------------------- lifecycle

    override fun onMainDestroy() {
        if (scopeCreated) {
            try {
                teardown()
            } catch (t: Throwable) {
                Log.w(TAG, "teardown on destroy failed", t)
            }
            try { scope.cancel() } catch (_: Throwable) { }
        }
        super.onMainDestroy()
    }

    // ---------------------------------------------------------------- internals

    private suspend fun doConnect(url: String, token: String, publish: Boolean) {
        val ctx: Context = activity?.applicationContext ?: context.applicationContext
        teardown()
        canPublish = publish
        micOn = false
        emitState("connecting")
        val job = scope.launch {
            val r = try {
                LiveKit.create(ctx, RoomOptions(adaptiveStream = false, dynacast = false))
            } catch (t: Throwable) {
                fail("create_failed: ${t.message}")
                return@launch
            }
            room = r
            configureAudio(r)
            eventsJob = scope.launch {
                try {
                    r.events.collect { ev -> onRoomEvent(r, ev) }
                } catch (c: CancellationException) {
                    throw c
                } catch (t: Throwable) {
                    Log.w(TAG, "event stream failed", t)
                }
            }
            try {
                r.connect(url, token)
            } catch (c: CancellationException) {
                throw c
            } catch (t: Throwable) {
                if (room === r) fail("connect_failed: ${t.message}")
                return@launch
            }
            if (room !== r) return@launch
            forceSpeakerphone(r)
            applySpeaker(r)
            emitState("on")
        }
        connectJob = job
    }

    private suspend fun doSetMic(on: Boolean) {
        val r = room ?: return
        if (!canPublish) {
            if (on) emitError("mic:not_allowed")
            return
        }
        try {
            r.localParticipant.setMicrophoneEnabled(on)
            micOn = on
        } catch (c: CancellationException) {
            throw c
        } catch (t: Throwable) {
            micOn = false
            emitError("mic:${t.message ?: "failed"}")
        }
    }

    private fun onRoomEvent(r: Room, ev: RoomEvent) {
        if (room !== r) return
        when (ev) {
            is RoomEvent.ActiveSpeakersChanged ->
                emitSpeakers(ev.speakers.mapNotNull { it.identity?.value })
            is RoomEvent.TrackSubscribed -> {
                val t = ev.track
                if (t is RemoteAudioTrack) {
                    try { t.setVolume(if (speakerOn) 1.0 else 0.0) } catch (_: Throwable) { }
                }
            }
            is RoomEvent.Disconnected -> {
                // While connecting, the failing connect() call reports the error itself.
                if (lastState != "on") return
                teardown()
                emitSpeakers(emptyList())
                emitState("off")
            }
            else -> Unit
        }
    }

    /** LiveKit's AudioSwitchHandler owns routing/focus; prefer BT → wired → loudspeaker → earpiece. */
    private fun configureAudio(r: Room) {
        try {
            r.audioSwitchHandler?.let { h ->
                h.preferredDeviceList = listOf(
                    AudioDevice.BluetoothHeadset::class.java,
                    AudioDevice.WiredHeadset::class.java,
                    AudioDevice.Speakerphone::class.java,
                    AudioDevice.Earpiece::class.java,
                )
                h.audioMode = AudioManager.MODE_IN_COMMUNICATION
            }
        } catch (t: Throwable) {
            Log.w(TAG, "audio config failed", t)
        }
    }

    /** Game voice chat is hands-free: if routing landed on the earpiece, switch to the loudspeaker. */
    @Suppress("DEPRECATION")
    private fun forceSpeakerphone(r: Room) {
        try {
            val h = r.audioSwitchHandler
            if (h != null) {
                val sel = h.selectedAudioDevice
                if (sel == null || sel is AudioDevice.Earpiece) {
                    h.availableAudioDevices.firstOrNull { it is AudioDevice.Speakerphone }?.let { h.selectDevice(it) }
                }
                return
            }
            val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            if (savedSpeakerphone == null) savedSpeakerphone = am.isSpeakerphoneOn
            am.isSpeakerphoneOn = true
        } catch (t: Throwable) {
            Log.w(TAG, "speakerphone failed", t)
        }
    }

    private fun applySpeaker(r: Room) {
        val vol = if (speakerOn) 1.0 else 0.0
        try {
            for (p in r.remoteParticipants.values) {
                for ((_, track) in p.audioTrackPublications) {
                    if (track is RemoteAudioTrack) track.setVolume(vol)
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "volume failed", t)
        }
        try { r.setSpeakerMute(!speakerOn) } catch (_: Throwable) { }
    }

    private fun teardown() {
        connectJob?.cancel(); connectJob = null
        eventsJob?.cancel(); eventsJob = null
        val r = room
        room = null
        micOn = false
        if (r != null) {
            try { r.disconnect() } catch (t: Throwable) { Log.w(TAG, "disconnect failed", t) }
            try { r.release() } catch (t: Throwable) { Log.w(TAG, "release failed", t) }
        }
        savedSpeakerphone?.let { prev ->
            try {
                @Suppress("DEPRECATION")
                (context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)?.isSpeakerphoneOn = prev
            } catch (_: Throwable) { }
            savedSpeakerphone = null
        }
    }

    private fun fail(msg: String) {
        Log.w(TAG, msg)
        teardown()
        emitError(msg)
        emitState("error")
    }

    private fun emitState(s: String) {
        lastState = s
        safeEmit(SIG_STATE, s)
    }

    private fun emitSpeakers(ids: List<String>) {
        val a = JSONArray()
        ids.forEach { a.put(it) }
        safeEmit(SIG_SPEAKERS, a.toString())
    }

    private fun emitError(msg: String) {
        safeEmit(SIG_ERROR, msg)
    }
}
