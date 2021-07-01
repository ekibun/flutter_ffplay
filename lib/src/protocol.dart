part of '../ffmpeg.dart';

class _WrapIsolateProtocolRequest extends ffi.ProtocolRequest {
  _IsolateFunction _cb;
  _WrapIsolateProtocolRequest(this._cb, int bufferSize) : super(bufferSize);
  @override
  Future close() => _cb.call({
        #type: #close,
      });

  @override
  int read(Pointer<Uint8> buf, int size) => _cb.callSync({
        #type: #read,
        #buf: buf.address,
        #size: size,
      });

  @override
  int seek(int offset, int whence) => _cb.callSync({
        #type: #seek,
        #offset: offset,
        #whence: whence,
      });
}

abstract class ProtocolRequest extends _IsolateEncodable {
  final int bufferSize;
  Future<int> read(Uint8List buf);
  Future<int> seek(int offset, int whence);
  Future<void> closeImpl();
  bool _isCancel = false;
  bool get isCancel => _isCancel;

  Future close() async {
    _isCancel = true;
    await closeImpl();
    __functions?.destroy();
    __functions = null;
  }

  ProtocolRequest(this.bufferSize);

  _IsolateFunction? __functions;
  _IsolateFunction get _functions {
    if (__functions == null)
      __functions = _IsolateFunction._new((msg) async {
        _isCancel = false;
        switch (msg[#type]) {
          case #read:
            return read(
              Pointer<Uint8>.fromAddress(msg[#buf]).asTypedList(msg[#size]),
            );
          case #seek:
            return seek(
              msg[#offset],
              msg[#whence],
            );
          case #close:
            return close();
        }
      });
    return __functions!;
  }

  @override
  Map _encode() => {
        #urlProtocolBufferSize: bufferSize,
        #urlProtocolCallback: _functions._encode(),
      };

  static ffi.ProtocolRequest? _decode(Map obj) {
    if (obj.containsKey(#urlProtocolCallback)) {
      return _WrapIsolateProtocolRequest(
        _IsolateFunction._decode(obj[#urlProtocolCallback])!,
        obj[#urlProtocolBufferSize],
      );
    }

    return null;
  }
}
