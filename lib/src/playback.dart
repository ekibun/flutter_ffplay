part of '../ffmpeg.dart';

final MethodChannel _channel = const MethodChannel('player');

class Playback {
  Pointer<ffi.PlaybackClient>? _playback;
  final int textureId;

  Playback(this.textureId);

  static Future<Playback> create() async {
    final int ptr = await _channel.invokeMethod('createPlayback');
    final int textureId = await _channel.invokeMethod('getTextureId', ptr);
    return Playback(textureId).._playback = Pointer.fromAddress(ptr);
  }

  void _postFrame(int codecType, FFMpegFrame frame) async {
    _playback?.postFrame(codecType, frame._p!);
  }

  Future<int> _flushFrame(int codecType, FFMpegFrame frame) async {
    switch (codecType) {
      case ffi.AVMediaType.AUDIO:
        final offset = await _playback?.flushAudioBuffer();
        return offset != null ? frame._pts - offset : -1;
      case ffi.AVMediaType.VIDEO:
        _playback?.flushVideoBuffer();
        return -1;
    }
    throw UnsupportedError('unsupported codec type $codecType');
  }

  void start() {
    _playback?.start();
  }

  void stop() {
    _playback?.stop();
  }

  void close() async {
    _playback?.close();
    _playback = null;
  }
}
