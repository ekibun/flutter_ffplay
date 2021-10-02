part of '../flutter_ffplay.dart';

class FormatContext {
  Future<_IsolateFunction>? _isolate;
  final String url;
  final IOHandler _ioHandler;

  FormatContext(this.url, this._ioHandler);

  _ensureIsolate() {
    if (_isolate != null) return;
    ReceivePort port = ReceivePort();
    Isolate.spawn(
      _runIsolate,
      {
        #port: port.sendPort,
        #init: _initReaderIsolate,
        #handle: _handleReaderIsolate,
        #ioHandler: _ioHandler._encode(),
        #url: url,
      },
      debugName: 'FormatContext',
      errorsAreFatal: true,
    );
    _isolate = port.first.then((result) {
      port.close();
      if (result is Map && result.containsKey(#error)) {
        throw _decodeData(result[#error], _isolateDecoders);
      }
      return _decodeData(result, _isolateDecoders) as _IsolateFunction;
    });
  }

  static ffi.FormatContext _initReaderIsolate(Map spawnMessage) {
    final io = IOHandler._decode(spawnMessage[#ioHandler])!;
    final ctx = ffi.FormatContext(spawnMessage[#url], io);
    return ctx;
  }

  static _handleReaderIsolate(ffi.FormatContext ctx, dynamic msg) async {
    switch (msg[#type]) {
      case #getPacket:
        final streams = List<FFMpegStream>.from(msg[#streams]);
        var packet = malloc<Pointer<ffi.AVPacket>>();
        packet.value = Pointer.fromAddress(0);
        var packetAddr = 0;
        while (ctx.getPacket(packet) == 0) {
          final streamIndex = packet.value.streamIndex;
          if (streams.isNotEmpty) {
            final stream = streams.indexWhere((s) => s.index == streamIndex);
            if (stream < 0) continue;
          }
          packetAddr = packet.value.address;
          break;
        }
        malloc.free(packet);
        return packetAddr;
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

  Future<Pointer<ffi.AVPacket>> getPacket(List<FFMpegStream> streams) async {
    _ensureIsolate();
    return await (await _isolate!)({
      #type: #getPacket,
      #streams: streams,
    }).then((ptr) => Pointer.fromAddress(ptr));
  }

  Future close() async {
    if (_isolate == null) return;
    final ret = _isolate?.then((isolate) async {
      final closePort = ReceivePort();
      await isolate({
        #type: #close,
        #port: closePort.sendPort,
      });
      isolate.destroy();
    }).catchError((_) {});
    _isolate = null;
    return ret;
  }
}
