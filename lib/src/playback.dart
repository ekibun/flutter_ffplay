part of '../ffmpeg.dart';

class Playback {
  Pointer<ffi.AudioClient>? __audio;
  Pointer<ffi.AudioClient> get audio =>
      __audio ??= ffi.PointerAudioClient.create()..start();
  void _postFrame(int codecType, FFMpegFrame frame) async {
    switch (codecType) {
      case ffi.AVMediaType.AUDIO:
        audio.postFrame(frame._p!);
        break;
      case ffi.AVMediaType.VIDEO:
        break;
    }
  }

  Future<int> _flushFrame(int codecType, FFMpegFrame frame) async {
    switch (codecType) {
      case ffi.AVMediaType.AUDIO:
        return frame._pts - (await audio.flushBuffer());
      case ffi.AVMediaType.VIDEO:
        return -1;
    }
    throw UnsupportedError('unsupported codec type $codecType');
  }

  void start() {
    __audio?.start();
  }

  void stop() {
    __audio?.stop();
  }

  void close() {
    __audio?.close();
    __audio = null;
  }
}
