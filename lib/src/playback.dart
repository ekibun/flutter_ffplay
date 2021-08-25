part of '../flutter_ffplay.dart';

abstract class Playback {
  Pointer<ffi.SWContext>? _sw;
  final int textureId;
  final int audioBufferTime;
  final void Function(int?)? _onFrame;

  int get width => _sw?.ref.width ?? 0;
  int get height => _sw?.ref.height ?? 0;

  double get speedRatio => _sw?.ref.speedRatio ?? 1;
  set speedRatio(double d) => _sw?.ref.speedRatio = d;

  double get aspectRatio {
    final _h = height;
    return _h == 0 ? 1 : width / _h;
  }

  Playback(
    this.textureId,
    this.audioBufferTime,
    int sampleRate,
    int channels,
    int audioFormat,
    int videoFormat, {
    void Function(int?)? onFrame,
  }) : _onFrame = onFrame {
    final sw = _sw = ffi.mallocSWContext();
    sw.ref.speedRatio = 1;
    sw.ref.sampleRate = sampleRate;
    sw.ref.channels = channels;
    sw.ref.audioFormat = audioFormat;
    sw.ref.videoFormat = videoFormat;
  }

  static Future<Playback> create({
    void Function(int?)? onFrame,
  }) async {
    final data = await _channel.invokeMethod("create");
    return _PlaybackImpl._(
      data["ctx"],
      data["textureId"],
      data["audioBufferTime"],
      data["sampleRate"],
      data["channels"],
      data["audioFormat"],
      data["videoFormat"],
      onFrame,
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
            await _flushAudioBuffer(sw.ref.audioBuffer, sw.ref.audioBufferSize);
        return offset < 0
            ? -1
            : frame.timestamp - offset * ffi.AV_TIME_BASE ~/ sw.ref.sampleRate;
      case ffi.AVMediaType.VIDEO:
        flushVideoBuffer(sw.ref.videoBuffer, sw.ref.videoBufferSize,
            sw.ref.width, sw.ref.height);
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
      await Future.delayed(Duration(milliseconds: audioBufferTime ~/ 2));
    }
  }

  Future<int> flushAudioBuffer(
    Pointer<Uint8> buffer,
    int length,
  );

  Future flushVideoBuffer(
    Pointer<Uint8> buffer,
    int length,
    int width,
    int height,
  );

  Future resume();

  Future pause();

  Future stop();

  Future close() async {
    if (_sw != null) malloc.free(_sw!);
    _sw = null;
  }
}

const _channel = MethodChannel('flutter_ffplay');

class _PlaybackImpl extends Playback {
  int? _ctx;
  _PlaybackImpl._(
      this._ctx,
      int textureId,
      int audioBufferSize,
      int sampleRate,
      int channels,
      int audioFormat,
      int videoFormat,
      void Function(int?)? onFrame)
      : super(textureId, audioBufferSize, sampleRate, channels, audioFormat,
            videoFormat,
            onFrame: onFrame);

  @override
  Future<int> flushAudioBuffer(Pointer<Uint8> buffer, int length) async {
    return await _channel.invokeMethod("flushAudioBuffer", {
      "ctx": _ctx!,
      "buffer": buffer.address,
      "length": length,
    });
  }

  @override
  Future flushVideoBuffer(
      Pointer<Uint8> buffer, int length, int width, int height) async {
    return await _channel.invokeMethod("flushVideoBuffer", {
      "ctx": _ctx!,
      "buffer": buffer.address,
      "length": length,
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
