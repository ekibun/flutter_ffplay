import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_ffplay/ffmpeg.dart';

class _BytesBuffer {
  static const int _initSize = 1024;
  static final _emptyList = Uint8List(0);
  int _length = 0;
  Uint8List _buffer;

  _BytesBuffer() : _buffer = _emptyList;

  void add(List<int> bytes) {
    int byteCount = bytes.length;
    if (byteCount == 0) return;
    int required = _length + byteCount;
    if (_buffer.length < required) {
      _grow(required);
    }
    assert(_buffer.length >= required);
    if (bytes is Uint8List) {
      _buffer.setRange(_length, required, bytes);
    } else {
      for (int i = 0; i < byteCount; i++) {
        _buffer[_length + i] = bytes[i];
      }
    }
    _length = required;
  }

  int takeBytes(Uint8List target) {
    final byteTaken = min(target.length, _length);
    target.setRange(0, byteTaken, _buffer);
    takeOut(byteTaken);
    return byteTaken;
  }

  void takeOut(int byteTaken) {
    _length -= byteTaken;
    _buffer.setRange(
      0,
      _length,
      Uint8List.view(
        _buffer.buffer,
        _buffer.offsetInBytes + byteTaken,
        _length,
      ),
    );
  }

  void _grow(int required) {
    int newSize = required * 2;
    if (newSize < _initSize) {
      newSize = _initSize;
    } else {
      newSize = _pow2roundup(newSize);
    }
    var newBuffer = Uint8List(newSize);
    newBuffer.setRange(0, _buffer.length, _buffer);
    _buffer = newBuffer;
  }

  static int _pow2roundup(int x) {
    assert(x > 0);
    --x;
    x |= x >> 1;
    x |= x >> 2;
    x |= x >> 4;
    x |= x >> 8;
    x |= x >> 16;
    return x + 1;
  }
}

class _HttpResponse {
  int pos;
  final buffer = _BytesBuffer();
  final HttpClientResponse rsp;
  final StreamController _onData = StreamController.broadcast();
  late StreamSubscription _sub;
  bool get isClosed => _onData.isClosed;

  _HttpResponse(this.pos, this.rsp, int maxBufferSize) {
    _sub = rsp.listen((data) {
      buffer.add(data);
      _onData.add(null);
      if (buffer._length > maxBufferSize) _sub.pause();
    }, onDone: () => _onData.close());
  }

  close() async {
    _sub.cancel();
    (await rsp.detachSocket()).close();
  }
}

class HttpIOHandler extends IOHandler {
  final _client = HttpClient();

  HttpIOHandler([int bufferSize = 32768]) : super(bufferSize);
  @override
  Future<IOContext> open(String url) async {
    return HttpIOContext(Uri.parse(url), _client);
  }
}

class HttpIOContext extends IOContext {
  int _offset = 0;
  int _length = 0;
  final HttpClient _client;
  _HttpResponse? __rsp;

  Future<_HttpResponse> getRange(int start) async {
    final req = await _client.getUrl(url);
    req.headers.add(HttpHeaders.rangeHeader, "bytes=$start-");
    final rsp = await req.close();
    return _HttpResponse(rsp.statusCode == 206 ? _offset : 0, rsp, 128 * 1024);
  }

  Future<_HttpResponse> get _rsp async => __rsp ??= await getRange(_offset);
  Uri url;

  HttpIOContext(this.url, this._client);

  @override
  Future<int> read(Uint8List buf) async {
    final rsp = await _rsp;
    if (rsp._sub.isPaused) rsp._sub.resume();
    while (true) {
      final range = rsp.buffer.takeBytes(buf);
      if (range == 0 && rsp.isClosed) return -1;
      if (range == 0) {
        try {
          await rsp._onData.stream.first;
        } catch (e) {
          return -1;
        }
        continue;
      }
      _offset += range;
      return range;
    }
  }

  @override
  Future<int> seek(int offset, int whence) async {
    switch (whence) {
      case AVSEEK_SIZE:
        if (_length != 0) return _length;
        final rsp = await _rsp;
        if (rsp.rsp.statusCode == 206) {
          return _length = int.parse(rsp.rsp.headers
              .value(HttpHeaders.contentRangeHeader)!
              .split("/")
              .last);
        }
        return _length = rsp.rsp.contentLength;
      default:
        final rsp = __rsp;
        if (rsp != null &&
            _offset <= offset &&
            _offset + rsp.buffer._length > offset) {
          rsp.buffer.takeOut(offset - _offset);
        } else {
          __rsp?.close();
          __rsp = null;
        }
        _offset = offset;
        return 0;
    }
  }

  @override
  Future<int> close() async {
    await __rsp?.close();
    return 0;
  }
}
