part of '../ffmpeg.dart';

class CodecContext {
  final FFMpegStream _stream;
  Future<_IsolateFunction>? _isolate;

  CodecContext(this._stream);

  _ensureIsolate() {
    if (_isolate != null) return;
    ReceivePort port = ReceivePort();
    Isolate.spawn(
      _runIsolate,
      {
        #port: port.sendPort,
        #init: _initCodecIsolate,
        #handle: _handleCodecIsolate,
        #stream: _stream._p.address,
      },
      debugName: '_IsolateCodecContext',
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

  static ffi.CodecContext _initCodecIsolate(Map spawnMessage) {
    final stream = Pointer<ffi.AVStream>.fromAddress(spawnMessage[#stream]);
    return ffi.CodecContext(stream);
  }

  static _handleCodecIsolate(ffi.CodecContext ctx, dynamic msg) async {
    switch (msg[#type]) {
      case #sendPacketAndGetFrame:
        return ctx
            .sendPacketAndGetFrame(Pointer.fromAddress(msg[#packet]))
            .address;
      case #flush:
        ctx.flush();
        return;
      case #close:
        ctx.close();
        return _IsolateFunction._invokeHandler?.close();
      default:
        assert(false);
    }
  }

  Future<FFMpegFrame?> sendPacketAndGetFrame(
      Pointer<ffi.AVPacket> packet) async {
    _ensureIsolate();
    return await (await _isolate!)({
      #type: #sendPacketAndGetFrame,
      #packet: packet.address,
    }).then(
        (addr) => addr == 0 ? null : FFMpegFrame._(Pointer.fromAddress(addr)));
  }

  Future<void> flush() async {
    _ensureIsolate();
    return await (await _isolate!)({
      #type: #flush,
    });
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
    });
    _isolate = null;
    return ret;
  }
}
