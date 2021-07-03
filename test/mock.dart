import 'dart:ffi';

import 'package:ffmpeg/ffmpeg.dart';

final _ffilib = DynamicLibrary.open('./test/build/Debug/ffmpeg_plugin.dll');

class _PlaybackCtx extends Struct {
  @Int64()
  external int sampleRate;
  @Int64()
  external int channels;
  @Int64()
  external int audioFormat;
  @Int64()
  external int bufferFrameCount;
  external Pointer ctx;

  int _invoke(String method) {
    return _ffilib
        .lookupFunction<Int64 Function(Pointer), int Function(Pointer)>(
      "Mock_$method",
    )(ctx);
  }
}

final _createMockPlayback =
    _ffilib.lookupFunction<_PlaybackCtx Function(), _PlaybackCtx Function()>(
  'Mock_createPlayback',
);

final _audioWriteBuffer = _ffilib.lookupFunction<
    Int64 Function(Pointer, Pointer<Uint8>, Int64),
    int Function(Pointer, Pointer<Uint8>, int)>(
  'Mock_audioWriteBuffer',
);

class MockPlayback extends Playback {
  _PlaybackCtx _ctx;
  MockPlayback._(
    this._ctx,
  ) : super(0, _ctx.sampleRate, _ctx.channels, _ctx.audioFormat, -1);

  factory MockPlayback() {
    return MockPlayback._(_createMockPlayback());
  }

  @override
  Future pause() async {
    return _ctx._invoke("pause");
  }

  @override
  Future resume() async {
    return _ctx._invoke("resume");
  }

  @override
  Future stop() async {
    return _ctx._invoke("stop");
  }

  @override
  Future<int> flushAudioBuffer(Pointer<Uint8> buffer, int length) async {
    if (length <= 0) return _ctx._invoke("getCurrentPadding");
    return _audioWriteBuffer(_ctx.ctx, buffer, length);
  }

  @override
  Future flushVideoBuffer(Pointer<Uint8> buffer, int width, int height) async {}
}
