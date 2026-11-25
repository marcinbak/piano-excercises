package pl.dev4u.bak.piano_exercises

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterActivity() {
  private companion object {
    const val MAX_PENDING_CHUNKS = 12
    const val MAX_PCM_BYTES = 262_144
  }

  private var pcmChannel: MethodChannel? = null
  private val audioExecutor = Executors.newSingleThreadExecutor()
  private val streamGeneration = AtomicInteger(0)
  private val pendingChunks = AtomicInteger(0)
  private val trackLock = Any()
  private var audioTrack: AudioTrack? = null
  private var activeSampleRate: Int = 0

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val channel = MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "piano_exercises/pcm_audio"
    )
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        "enqueue" -> {
          val pcm = call.argument<ByteArray>("pcm")
          val sampleRate = call.argument<Number>("sampleRate")?.toInt() ?: 24000
          val isValid = pcm != null &&
            pcm.size in 2..MAX_PCM_BYTES &&
            pcm.size % 2 == 0 &&
            sampleRate in 8000..96000
          if (isValid && pcm != null && pendingChunks.get() < MAX_PENDING_CHUNKS) {
            val gen = streamGeneration.get()
            pendingChunks.incrementAndGet()
            audioExecutor.execute {
              try {
                writePcmChunk(pcm, sampleRate, gen)
              } finally {
                if (streamGeneration.get() == gen) {
                  pendingChunks.updateAndGet { count -> maxOf(0, count - 1) }
                }
              }
            }
          }
          result.success(null)
        }
        "stop" -> {
          stopAndFlushTrack()
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
    pcmChannel = channel
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    pcmChannel?.setMethodCallHandler(null)
    pcmChannel = null
    releaseTrack()
    super.cleanUpFlutterEngine(flutterEngine)
  }

  override fun onDestroy() {
    releaseTrack()
    audioExecutor.shutdownNow()
    super.onDestroy()
  }

  private fun writePcmChunk(pcm: ByteArray, sampleRate: Int, generation: Int) {
    if (streamGeneration.get() != generation) return
    try {
      val track = synchronized(trackLock) {
        if (streamGeneration.get() != generation) null else ensureTrackLocked(sampleRate)
      } ?: return
      track.write(pcm, 0, pcm.size, AudioTrack.WRITE_BLOCKING)
    } catch (_: Throwable) {
      // Audio route failure or concurrent track release must never crash the process.
    }
  }

  private fun ensureTrackLocked(sampleRate: Int): AudioTrack? {
    val existing = audioTrack
    if (existing != null &&
      activeSampleRate == sampleRate &&
      existing.state == AudioTrack.STATE_INITIALIZED
    ) {
      if (existing.playState != AudioTrack.PLAYSTATE_PLAYING) {
        existing.play()
      }
      return existing
    }
    try {
      existing?.release()
    } catch (_: Throwable) {}
    audioTrack = null
    activeSampleRate = 0

    val minBytes = AudioTrack.getMinBufferSize(
      sampleRate,
      AudioFormat.CHANNEL_OUT_MONO,
      AudioFormat.ENCODING_PCM_16BIT
    )
    if (minBytes <= 0) return null
    val bufferBytes = maxOf(minBytes, sampleRate)
    val created = AudioTrack.Builder()
      .setAudioAttributes(
        AudioAttributes.Builder()
          .setUsage(AudioAttributes.USAGE_MEDIA)
          .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
          .build()
      )
      .setAudioFormat(
        AudioFormat.Builder()
          .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
          .setSampleRate(sampleRate)
          .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
          .build()
      )
      .setTransferMode(AudioTrack.MODE_STREAM)
      .setBufferSizeInBytes(bufferBytes)
      .build()
    if (created.state != AudioTrack.STATE_INITIALIZED) {
      created.release()
      return null
    }
    activeSampleRate = sampleRate
    created.play()
    audioTrack = created
    return created
  }

  private fun stopAndFlushTrack() {
    streamGeneration.incrementAndGet()
    pendingChunks.set(0)
    synchronized(trackLock) {
      val existing = audioTrack ?: return
      try {
        if (existing.playState == AudioTrack.PLAYSTATE_PLAYING) {
          existing.pause()
        }
        existing.flush()
      } catch (_: Throwable) {}
    }
  }

  private fun releaseTrack() {
    streamGeneration.incrementAndGet()
    pendingChunks.set(0)
    synchronized(trackLock) {
      try {
        audioTrack?.stop()
      } catch (_: Throwable) {}
      try {
        audioTrack?.release()
      } catch (_: Throwable) {}
      audioTrack = null
      activeSampleRate = 0
    }
  }
}
