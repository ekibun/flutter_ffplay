import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:player/ffmpeg.dart';

class FileRequest extends ProtocolRequest {
  RandomAccessFile? file;

  FileRequest._new(this.file, [int bufferSize = 32768]) : super(bufferSize);

  static Future<FileRequest> open(String url) async {
    return FileRequest._new(await File(url).open());
  }

  @override
  Future closeImpl() async {
    await file?.close();
    file = null;
  }

  @override
  Future<int> read(Uint8List buf) async {
    final ret = await file?.readInto(buf) ?? 0;
    if (ret == 0) return -1;
    return ret;
  }

  @override
  Future<int> seek(int offset, int whence) async {
    switch (whence) {
      case AVSEEK_SIZE:
        return await file?.length() ?? -1;
      default:
        await file?.setPosition(offset);
        return 0;
    }
  }
}

class _HttpResponse {
  int pos;
  final buffer = <int>[];
  final HttpClientResponse rsp;
  final StreamController _onData = StreamController.broadcast();
  late StreamSubscription _sub;
  bool get isClosed => _onData.isClosed;

  _HttpResponse(this.pos, this.rsp, int maxBufferSize) {
    _sub = rsp.listen((data) {
      print("ondata[${data.length}]");
      // while (buffer.length > maxBufferSize)
      //   await Future.delayed(Duration(milliseconds: 10));
      buffer.addAll(data);
      _onData.add(buffer);
    }, onDone: () => _onData.close());
  }

  close() async {
    _sub.cancel();
  }
}

class HttpProtocolRequest extends ProtocolRequest {
  int _offset = 0;
  int _length = 0;
  _HttpResponse? __rsp;

  Future<_HttpResponse> getRange(int start) async {
    print('get range $url $start');
    final req = await HttpClient().getUrl(url);
    req.headers.add(HttpHeaders.rangeHeader, "bytes=$start-");
    final rsp = await req.close();
    return _HttpResponse(
        rsp.statusCode == 206 ? _offset : 0, rsp, 5 * bufferSize);
  }

  Future<_HttpResponse> get _rsp async => __rsp ??= await getRange(_offset);
  Uri url;

  HttpProtocolRequest(this.url, [int bufferSize = 32768]) : super(bufferSize);

  @override
  Future<void> closeImpl() async {}

  @override
  Future<int> read(Uint8List buf) async {
    final rsp = await _rsp;
    while (true) {
      final range = min(rsp.buffer.length, buf.length);
      if (range == 0 && rsp.isClosed) return -1;
      if (range == 0) {
        await rsp._onData.stream.first;
        continue;
      }
      _offset += range;
      buf.setRange(0, range, rsp.buffer);
      rsp.buffer.removeRange(0, range);
      return range;
    }
  }

  @override
  Future<int> seek(int offset, int whence) async {
    switch (whence) {
      case AVSEEK_SIZE:
        if (_length != 0) return _length;
        final rsp = await _rsp;
        if (rsp.rsp.statusCode == 206)
          return _length = int.parse(rsp.rsp.headers
              .value(HttpHeaders.contentRangeHeader)!
              .split("/")
              .last);
        return _length = rsp.rsp.contentLength;
      default:
        final rsp = __rsp;
        if (rsp != null &&
            _offset <= offset &&
            _offset + rsp.buffer.length > offset) {
          print("good!");
          rsp.buffer.removeRange(0, offset - _offset);
        } else {
          print("bad $_offset -> $offset");
          __rsp?.close();
          __rsp = null;
        }
        _offset = offset;
        return 0;
    }
  }
}
