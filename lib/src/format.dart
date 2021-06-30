part of '../ffmpeg.dart';

class FormatContext {
  Future<_IsolateFunction>? _isolate;
  final ProtocolRequest _req;

  FormatContext(this._req);

  _ensureIsolate() {
    if (_isolate != null) return;
    ReceivePort port = ReceivePort();
    Isolate.spawn(
      _runIsolate,
      {
        #port: port.sendPort,
        #init: _initReaderIsolate,
        #handle: _handleReaderIsolate,
        #request: _req._encode(),
      },
      debugName: 'FormatContext',
      errorsAreFatal: true,
    );
    _isolate = port.first.then((result) {
      port.close();
      if (result is Map && result.containsKey(#error))
        throw _decodeData(result[#error], _isolateDecoders);
      return _decodeData(result, _isolateDecoders) as _IsolateFunction;
    });
  }

  static ffi.AVFormatContext _initReaderIsolate(Map spawnMessage) {
    final request = _decodeData(spawnMessage[#request], _isolateDecoders);
    final ctx = ffi.AVFormatContext(request);
    return ctx;
  }

  static _handleReaderIsolate(ffi.AVFormatContext ctx, dynamic msg) async {
    switch (msg[#type]) {
      case #getStreams:
        int index = 0;
        return ctx.getStreams().map((p) => FFMpegStream._(index++, p)).toList();
      case #getDuration:
        return ctx.getDuration();
      case #seekTo:
        return ctx.seekTo(
          msg[#ts],
          streamIndex: msg[#streamIndex],
          minTs: msg[#minTs],
          maxTs: msg[#maxTs],
          flags: msg[#flags],
        );
      case #close:
        await ctx.close();
        return _IsolateFunction._invokeHandler?.close();
    }
  }

  Future seekTo(
    int ts, {
    int streamIndex = -1,
    int minTs = ffi.INT64_MIN,
    int maxTs = ffi.INT64_MAX,
    int flags = 0,
  }) async {
    _ensureIsolate();
    return (await _isolate!)({
      #type: #seekTo,
      #ts: ts,
      #streamIndex: streamIndex,
      #minTs: minTs,
      #maxTs: maxTs,
      #flags: flags,
    });
  }

  Future<List<FFMpegStream>> getStreams() async {
    _ensureIsolate();
    return List<FFMpegStream>.from(await (await _isolate!)({
      #type: #getStreams,
    }));
  }

  Future<int> getDuration() async {
    _ensureIsolate();
    return await (await _isolate!)({
      #type: #getDuration,
    });
  }

  close() async {
    if (_isolate == null) return;
    final ret = _isolate?.then((isolate) async {
      final closePort = ReceivePort();
      await isolate({
        #type: #close,
        #port: closePort.sendPort,
      });
      isolate.destroy();
      _req.close();
    });
    _isolate = null;
    return ret;
  }
}
