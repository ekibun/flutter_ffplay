package soko.ekibun.ffmpeg

import android.graphics.Bitmap
import android.graphics.Paint
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.util.Log
import android.view.Surface
import androidx.annotation.RequiresApi
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer

@RequiresApi(Build.VERSION_CODES.M)
class PlaybackImpl(
        val texture: TextureRegistry.SurfaceTextureEntry
) {
  companion object {
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

  val audio by lazy {
    val defaultRate = 48000
    val defaultChannel = AudioFormat.CHANNEL_OUT_STEREO
    val defaultFormat = AudioFormat.ENCODING_PCM_8BIT
    AudioTrack.Builder()
            .setAudioFormat(AudioFormat.Builder()
                    .setSampleRate(defaultRate)
                    .setChannelMask(defaultChannel)
                    .setEncoding(defaultFormat)
                    .build()
            ).setBufferSizeInBytes(AudioTrack.getMinBufferSize(
                    defaultRate,
                    defaultChannel,
                    defaultFormat)).build()
  }

  val textureId
    get() = texture.id()
  val sampleRate = audio.sampleRate
  val channels = audio.channelCount
  val audioFormat = 0 // AV_SAMPLE_FMT_U8
  val videoFormat = 25 // AV_PIX_FMT_RGBA

  var buffered: ByteArray? = null;

  fun flushAudioBuffer(buffer: ByteArray): Int {
    // TODO fix audio lag
    if (buffer.isEmpty()) return 1
    return audio.write(ByteBuffer.wrap(buffer), buffer.size, AudioTrack.WRITE_BLOCKING)
  }

  var bitmap: Bitmap? = null

  val surfaceTexture by lazy { texture.surfaceTexture()!! }

  val surface by lazy { Surface(surfaceTexture) }

  val paint by lazy { Paint() }

  fun flushVideoBuffer(buffer: ByteArray, width: Int, height: Int): Int {
    surfaceTexture.setDefaultBufferSize(width, height)
    if(bitmap == null || bitmap?.width != width || bitmap?.height != height) {
      val oldBitmap = bitmap
      bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
      oldBitmap?.recycle()
    }
    bitmap!!.copyPixelsFromBuffer(ByteBuffer.wrap(buffer))
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
    Log.v("ffmpeg", "resume")
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