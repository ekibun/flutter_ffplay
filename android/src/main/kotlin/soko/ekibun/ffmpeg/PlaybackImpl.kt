package soko.ekibun.ffmpeg

import android.graphics.Bitmap
import android.graphics.Paint
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.view.Surface
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer

class PlaybackImpl(
        val texture: TextureRegistry.SurfaceTextureEntry
) {
  companion object {
    init {
      System.loadLibrary("ffmpeg")
    }

    const val defaultRate = 48000
    const val defaultChannel = AudioFormat.CHANNEL_OUT_STEREO
    const val defaultFormat = AudioFormat.ENCODING_PCM_8BIT

    // Used to load the 'native-lib' library on application startup.
    private val instances by lazy { mutableMapOf<Int, PlaybackImpl>() }

    fun create(texture: TextureRegistry.SurfaceTextureEntry): Pair<Int, PlaybackImpl> {
      return PlaybackImpl(texture).let {
        val key = System.identityHashCode(it)
        instances[key] = it
        key to it
      }
    }

    fun get(key: Int): PlaybackImpl {
      return instances[key]!!
    }

    fun close(key: Int) {
      instances.remove(key)?.close()
    }
  }

  external fun getByteBuffer(buffer: Long, length: Int): ByteArray

  val audioBufferSize by lazy {
    AudioTrack.getMinBufferSize(
            defaultRate,
            defaultChannel,
            defaultFormat)
  }
  val audio by lazy {
    val audioMode = AudioTrack.MODE_STREAM
    if (Build.VERSION.SDK_INT < 21) {
      @Suppress("DEPRECATION")
      AudioTrack(
              AudioManager.STREAM_MUSIC,
              defaultRate,
              defaultChannel,
              defaultFormat,
              audioBufferSize,
              audioMode)
    } else {
      AudioTrack(
              AudioAttributes.Builder().build(),
              AudioFormat.Builder()
                      .setSampleRate(defaultRate)
                      .setChannelMask(defaultChannel)
                      .setEncoding(defaultFormat)
                      .build(),
              audioBufferSize,
              audioMode,
              AudioManager.AUDIO_SESSION_ID_GENERATE
      )
    }
  }

  val textureId
    get() = texture.id()
  val sampleRate = audio.sampleRate
  val channels = audio.channelCount
  val audioFormat = 0 // AV_SAMPLE_FMT_U8
  val videoFormat = 25 // AV_PIX_FMT_RGBA

  fun flushAudioBuffer(buffer: Long, length: Int): Int {
    if (length <= 0) return 0
    return audio.write(getByteBuffer(buffer, length), 0, length)
  }

  var bitmap: Bitmap? = null

  val surfaceTexture by lazy { texture.surfaceTexture()!! }

  val surface by lazy { Surface(surfaceTexture) }

  val paint by lazy { Paint() }

  fun flushVideoBuffer(buffer: Long, length: Int, width: Int, height: Int): Int {
    surfaceTexture.setDefaultBufferSize(width, height)
    if (bitmap == null || bitmap?.width != width || bitmap?.height != height) {
      val oldBitmap = bitmap
      bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
      oldBitmap?.recycle()
    }
    bitmap!!.copyPixelsFromBuffer(ByteBuffer.wrap(getByteBuffer(buffer, length)))
    val canvas = surface.lockCanvas(null)
    canvas.drawBitmap(bitmap!!, 0f, 0f, paint)
    surface.unlockCanvasAndPost(canvas)
    return -1
  }

  fun pause(): Int {
    audio.pause()
    return 0
  }

  fun resume(): Int {
    audio.play()
    return 0
  }

  fun stop(): Int {
    audio.pause()
    audio.flush()
    return 0
  }

  fun close() {
    audio.release()
    texture.release()
  }
}