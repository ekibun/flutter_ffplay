part of '../ffmpeg.dart';

class _WrapIOContext extends ffi.IOContext {
  final _IsolateFunction _cb;
  _WrapIOContext(this._cb, int bufferSize) : super(bufferSize);
  @override
  int close(int key) => _cb.callSync({
        #type: #close,
        #key: key,
      });

  @override
  int read(int key, Pointer<Uint8> buf, int size) => _cb.callSync({
        #type: #read,
        #key: key,
        #buf: buf.address,
        #size: size,
      });

  @override
  int seek(int key, int offset, int whence) => _cb.callSync({
        #type: #seek,
        #key: key,
        #offset: offset,
        #whence: whence,
      });

  @override
  int open(String url) => _cb.callSync({
        #type: #open,
        #url: url,
      });
}

abstract class IOContext {
  Future<int> read(Uint8List buf);
  Future<int> seek(int offset, int whence);
  Future<int> close();
}

abstract class IOHandler extends _IsolateEncodable {
  final int bufferSize;
  final _ctx = <int, IOContext>{};

  Future<IOContext> open(String url);
  bool _isCancel = false;
  bool get isCancel => _isCancel;

  Future destroy() async {
    _isCancel = true;
    __functions?.destroy();
    __functions = null;
  }

  IOHandler(this.bufferSize);

  _IsolateFunction? __functions;
  _IsolateFunction get _functions {
    __functions ??= _IsolateFunction._new((msg) async {
      _isCancel = false;
      switch (msg[#type]) {
        case #open:
          final ctx = await open(msg[#url]);
          final key = identityHashCode(ctx);
          _ctx[key] = ctx;
          return key;
        case #read:
          return _ctx[msg[#key]]!.read(
            Pointer<Uint8>.fromAddress(msg[#buf]).asTypedList(msg[#size]),
          );
        case #seek:
          return _ctx[msg[#key]]!.seek(
            msg[#offset],
            msg[#whence],
          );
        case #close:
          return _ctx.remove(msg[#key])!.close();
      }
    });
    return __functions!;
  }

  @override
  Map _encode() => {
        #urlProtocolBufferSize: bufferSize,
        #urlProtocolCallback: _functions._encode(),
      };

  static ffi.IOContext? _decode(Map obj) {
    if (obj.containsKey(#urlProtocolCallback)) {
      return _WrapIOContext(
        _IsolateFunction._decode(obj[#urlProtocolCallback])!,
        obj[#urlProtocolBufferSize],
      );
    }

    return null;
  }
}
