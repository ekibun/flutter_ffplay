part of '../ffmpeg.dart';

class FfmpegStream implements _IsolateEncodable {
  final int index;
  Pointer<ffi.AVStream> _p;
  FfmpegStream._new(this.index, this._p);

  int _getFramePts(Pointer<ffi.AVFrame> frame) {
    return getFrameTimeStamp(frame, _p);
  }

  int get codecType => _p.codecpar.codec_type;

  @override
  Map _encode() => {
        #streamIndex: index,
        #streamPtr: _p.address,
      };

  static FfmpegStream? _decode(Map data) {
    if (data.containsKey(#streamPtr))
      return FfmpegStream._new(
        data[#streamIndex],
        Pointer.fromAddress(data[#streamPtr]),
      );
    return null;
  }
}

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
      debugName: '_IsolateFormatContext',
      errorsAreFatal: true,
    );
    _isolate = port.first.then((result) {
      port.close();
      if (result is Map && result.containsKey(#error))
        throw _decodeData(result[#error], _isolateDecoders);
      return _decodeData(result, _isolateDecoders) as _IsolateFunction;
    });
  }

  static ffi.FormatContext _initReaderIsolate(Map spawnMessage) {
    final request = _decodeData(spawnMessage[#request], _isolateDecoders);
    final ctx = ffi.FormatContext(request);
    return ctx;
  }

  static _handleReaderIsolate(ffi.FormatContext ctx, dynamic msg) async {
    switch (msg[#type]) {
      case #getPacket:
        return ctx.getPacket(List<FfmpegStream>.from(msg[#streams]));
      case #getStreams:
        return ctx.getStreams();
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

  Future<List<FfmpegStream>> getStreams() async {
    _ensureIsolate();
    return List<FfmpegStream>.from(await (await _isolate!)({
      #type: #getStreams,
    }));
  }

  Future<int> duration() async {
    _ensureIsolate();
    return await (await _isolate!)({
      #type: #duration,
    });
  }

  Future<Packet?> getPacket(List<FfmpegStream> streams) async {
    _ensureIsolate();
    return await (await _isolate!)({
      #type: #getPacket,
      #streams: streams,
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
      _req?.close();
      _req = null;
    });
    _isolate = null;
    return ret;
  }
}
