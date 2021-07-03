part of '../ffmpeg.dart';

abstract class Playback {
  Pointer<ffi.SWContext>? _sw;
  final int textureId;

  Playback(
    this.textureId,
    int sampleRate,
    int channels,
    int audioFormat,
    int videoFormat,
  ) {
    final sw = _sw = ffi.mallocSWContext();
    sw.ref.sampleRate = sampleRate;
    sw.ref.channels = channels;
    sw.ref.audioFormat = audioFormat;
    sw.ref.videoFormat = videoFormat;
  }

  static Future<Playback> create() async {
    final data = await _channel.invokeMethod("create");
    return _PlaybackImpl._(
      data["ctx"],
      data["textureId"],
      data["sampleRate"],
      data["channels"],
      data["audioFormat"],
      data["videoFormat"],
    );
  }

  void _postFrame(int codecType, FFMpegFrame frame) async {
    _sw?.postFrame(codecType, frame._p!);
  }

  Future<int> _flushFrame(int codecType, FFMpegFrame frame) async {
    final sw = _sw!;
    switch (codecType) {
      case ffi.AVMediaType.AUDIO:
        final offset =
            await _flushAudioBuffer(sw.ref.audioBuffer, sw.ref.bufferSamples);
        return offset <= 0
            ? -1
            : frame.timestamp - offset * ffi.AV_TIME_BASE ~/ sw.ref.sampleRate;
      case ffi.AVMediaType.VIDEO:
        flushVideoBuffer(sw.ref.videoBuffer, sw.ref.width, sw.ref.height);
        return -1;
    }
    return -1;
  }

  Future<int> _flushAudioBuffer(Pointer<Uint8> buffer, int length) async {
    int offset = 0;
    while (true) {
      final o = await flushAudioBuffer(
        buffer.elementAt(offset),
        length - offset,
      );
      if (offset >= length) return o;
      if (o < 0) return -1;
      offset += o;
      if (offset >= length) continue;
      if (_sw == null) return -1;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<int> flushAudioBuffer(Pointer<Uint8> buffer, int length);

  Future flushVideoBuffer(Pointer<Uint8> buffer, int width, int height);

  Future resume();

  Future pause();

  Future stop();

  Future close() async {
    if (_sw != null) malloc.free(_sw!);
    _sw = null;
  }
}

const _channel = MethodChannel('ffmpeg');

class _PlaybackImpl extends Playback {
  int? _ctx;
  _PlaybackImpl._(this._ctx, int textureId, int sampleRate, int channels,
      int audioFormat, int videoFormat)
      : super(textureId, sampleRate, channels, audioFormat, videoFormat);

  @override
  Future<int> flushAudioBuffer(Pointer<Uint8> buffer, int length) async {
    return await _channel.invokeMethod("flushAudioBuffer", {
      "ctx": _ctx!,
      "buffer": buffer.address,
      "length": length,
    });
  }

  @override
  Future flushVideoBuffer(Pointer<Uint8> buffer, int width, int height) async {
    return await _channel.invokeMethod("flushVideoBuffer", {
      "ctx": _ctx!,
      "buffer": buffer.address,
      "width": width,
      "height": height,
    });
  }

  @override
  Future pause() {
    return _channel.invokeMethod("pause", {
      "ctx": _ctx!,
    });
  }

  @override
  Future resume() {
    return _channel.invokeMethod("resume", {
      "ctx": _ctx!,
    });
  }

  @override
  Future stop() {
    return _channel.invokeMethod("stop", {
      "ctx": _ctx!,
    });
  }

  @override
  Future close() async {
    await super.close();
    final ctx = _ctx;
    _ctx = null;
    if (ctx == null) return;
    await _channel.invokeMethod("close", {
      "ctx": _ctx!,
    });
  }
}
