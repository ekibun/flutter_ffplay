package soko.ekibun.ffmpeg

class PlaybackImpl {
  companion object {
    // Used to load the 'native-lib' library on application startup.
    init {
        System.loadLibrary("ffmpeg")
    }
  }

  var textureId = 0;

  external fun bindNative(): Long

  external fun fromNative(ptr: Long): PlaybackImpl

  fun getCurrentPadding(): Int {
    print("getCurrentPadding")
    return 0
  }

  fun writeBuffer(buffer: ByteArray, length: Int): Int {
    print("writeBuffer")
    return -1;
  }

  fun flushVideoBuffer() {
    print("flushVideoBuffer")
  }

  fun start() {
    print("start")
  }

  fun stop() {
    print("stop")
  }

  fun close() {
    print("close")
  }
}