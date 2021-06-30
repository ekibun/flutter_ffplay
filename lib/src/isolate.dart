part of '../ffmpeg.dart';

typedef _DecodeFunc = dynamic Function(Map);

abstract class _IsolateEncodable {
  Map _encode();
}

class IsolateError extends _IsolateEncodable {
  late String message;
  late String stack;
  IsolateError(message, [stack]) {
    if (message is IsolateError) {
      this.message = message.message;
      this.stack = message.stack;
    } else {
      this.message = message.toString();
      this.stack = (stack ?? StackTrace.current).toString();
    }
  }

  @override
  String toString() {
    return stack.isEmpty ? message.toString() : "$message\n$stack";
  }

  static IsolateError? _decode(Map obj) {
    if (obj.containsKey(#jsError))
      return IsolateError(obj[#jsError], obj[#jsErrorStack]);
    return null;
  }

  @override
  Map _encode() {
    return {
      #jsError: message,
      #jsErrorStack: stack,
    };
  }
}

dynamic _encodeData(data, {Map<dynamic, dynamic>? cache}) {
  if (cache == null) cache = Map();
  if (cache.containsKey(data)) return cache[data];
  if (data is _IsolateEncodable) return data._encode();
  if (data is List) {
    final ret = [];
    cache[data] = ret;
    for (int i = 0; i < data.length; ++i) {
      ret.add(_encodeData(data[i], cache: cache));
    }
    return ret;
  }
  if (data is Map) {
    final ret = {};
    cache[data] = ret;
    for (final entry in data.entries) {
      ret[_encodeData(entry.key, cache: cache)] =
          _encodeData(entry.value, cache: cache);
    }
    return ret;
  }
  if (data is Pointer) return data.address;
  return data;
}

dynamic _decodeData(data, decoders, {Map<dynamic, dynamic>? cache}) {
  if (cache == null) cache = Map();
  if (cache.containsKey(data)) return cache[data];
  if (data is List) {
    final ret = [];
    cache[data] = ret;
    for (int i = 0; i < data.length; ++i) {
      ret.add(_decodeData(data[i], decoders, cache: cache));
    }
    return ret;
  }
  if (data is Map) {
    for (final decoder in decoders) {
      final decodeObj = decoder(data);
      if (decodeObj != null) return decodeObj;
    }
    final ret = {};
    cache[data] = ret;
    for (final entry in data.entries) {
      ret[_decodeData(entry.key, decoders, cache: cache)] =
          _decodeData(entry.value, decoders, cache: cache);
    }
    return ret;
  }
  return data;
}

final _isolateDecoders = <_DecodeFunc>[
  FFMpegStream._decode,
  _IsolateFunction._decode,
  IsolateError._decode,
  ProtocolRequest._decode,
];

void _runIsolate(Map spawnMessage) async {
  final SendPort sendPort = spawnMessage[#port];
  late final dynamic ctx;
  try {
    ctx = await spawnMessage[#init](spawnMessage);
  } catch (e, stack) {
    sendPort.send({
      #error: IsolateError(e, stack),
    });
  }
  sendPort.send(_IsolateFunction._new(
    (_msg) => spawnMessage[#handle](ctx, _msg),
  )._encode());
}

class _IsolateFunction implements _IsolateEncodable {
  int? _isolateId;
  SendPort? _port;
  dynamic _invokable;
  _IsolateFunction._fromId(this._isolateId, this._port);

  _IsolateFunction._new(this._invokable) {
    _handlers.add(this);
  }

  static ReceivePort? _invokeHandler;
  static Set<_IsolateFunction> _handlers = Set();

  static get _handlePort {
    if (_invokeHandler == null) {
      _invokeHandler = ReceivePort();
      _invokeHandler!.listen((msg) async {
        final msgPort = msg[#port];
        try {
          final handler = _handlers.firstWhere(
            (v) => identityHashCode(v) == msg[#handler],
          );
          final ret = await handler._handle(msg[#msg]);
          if (msg[#ptr] != null) {
            Pointer<IntPtr>.fromAddress(msg[#ptr]).value = ret;
          }
          if (msgPort != null) {
            msgPort.send(_encodeData(ret));
          }
        } catch (e, stack) {
          final err = _encodeData(IsolateError(e, stack));
          if (msg[#ptr] != null) {
            Pointer<IntPtr>.fromAddress(msg[#ptr]).value = -1;
            print(IsolateError(e, stack));
          }
          if (msgPort != null)
            msgPort.send({
              #error: err,
            });
        }
      });
    }
    return _invokeHandler!.sendPort;
  }

  _send(msg) async {
    if (_port == null) return _handle(msg);
    final evaluatePort = ReceivePort();
    _port!.send({
      #handler: _isolateId,
      #msg: msg,
      #port: evaluatePort.sendPort,
    });
    final result = await evaluatePort.first;
    if (result is Map && result.containsKey(#error))
      throw _decodeData(result[#error], _isolateDecoders);
    return _decodeData(result, _isolateDecoders);
  }

  _destroy() {
    _handlers.remove(this);
  }

  _handle(msg) async {
    switch (msg) {
      case #dup:
        _refCount++;
        return null;
      case #free:
        _refCount--;
        if (_refCount < 0) _destroy();
        return null;
      case #destroy:
        _destroy();
        return null;
    }
    final args = _decodeData(msg[#args], _isolateDecoders);
    return _invokable(args);
  }

  Future call(dynamic positionalArguments) async {
    return _send({
      #args: _encodeData(positionalArguments),
    });
  }

  int callSync(dynamic positionalArguments) {
    if (_port == null)
      return _handle({
        #args: _encodeData(positionalArguments),
      });
    final ptr = malloc<IntPtr>();
    ptr.value = ptr.address;
    _port!.send({
      #handler: _isolateId,
      #msg: {
        #args: _encodeData(positionalArguments),
      },
      #ptr: ptr.address,
    });
    while (ptr.value == ptr.address) sleep(Duration(milliseconds: 10));
    final ret = ptr.value;
    malloc.free(ptr);
    return ret;
  }

  static _IsolateFunction? _decode(Map obj) {
    if (obj.containsKey(#isolateFunctionPort))
      return _IsolateFunction._fromId(
        obj[#isolateFunctionId],
        obj[#isolateFunctionPort],
      );
    return null;
  }

  @override
  Map _encode() {
    return {
      #isolateFunctionId: _isolateId ?? identityHashCode(this),
      #isolateFunctionPort: _port ?? _IsolateFunction._handlePort,
    };
  }

  int _refCount = 0;

  dup() {
    _send(#dup);
  }

  free() {
    _send(#free);
  }

  void destroy() {
    _send(#destroy);
  }
}
