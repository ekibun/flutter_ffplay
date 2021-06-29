import 'dart:ffi';

const AVSEEK_SIZE = 0x10000;
const AVSEEK_FORCE = 0x20000;

const INT64_MIN = -0x8000000000000000;
const INT64_MAX = 0x7fffffffffffffff;

final _ffilib = DynamicLibrary.open('./test/build/Debug/player_plugin.dll');

class FFMpegFormatContext extends Opaque {}

class AVPacket extends Opaque {}

class AVStream extends Opaque {}

abstract class ProtocolRequest {
  final int bufferSize;
  int read(Pointer<Uint8> buf, int size);
  int seek(int offset, int whence);
  Future close();
  ProtocolRequest(
    this.bufferSize,
  );
}

final Map<int, ProtocolRequest> _protocolRequests = {};
const _readFailReturn = -1;
int _ioReadPacket(int opaque, Pointer<Uint8> buf, int bufSize) {
  return _protocolRequests[opaque]?.read(buf, bufSize) ?? _readFailReturn;
}

const _seekFailReturn = -1;
int _ioSeek(int opaque, int offset, int whence) {
  return _protocolRequests[opaque]?.seek(offset, whence) ?? _seekFailReturn;
}

class FormatContext {
  final ProtocolRequest req;
  Pointer<FFMpegFormatContext>? _this;
  static final _create = _ffilib.lookupFunction<
      Pointer<FFMpegFormatContext> Function(
          IntPtr,
          Int64,
          Pointer<
              NativeFunction<Int32 Function(IntPtr, Pointer<Uint8>, Int32)>>,
          Pointer<NativeFunction<Int64 Function(IntPtr, Int64, Int32)>>),
      Pointer<FFMpegFormatContext> Function(
          int,
          int,
          Pointer<
              NativeFunction<Int32 Function(IntPtr, Pointer<Uint8>, Int32)>>,
          Pointer<NativeFunction<Int64 Function(IntPtr, Int64, Int32)>>)>(
    'FFMpegFormatContext_create',
  );

  FormatContext(this.req) {
    final idReq = identityHashCode(req);
    _protocolRequests[idReq] = req;
    _this = _create(
        idReq,
        req.bufferSize,
        Pointer.fromFunction(_ioReadPacket, _readFailReturn),
        Pointer.fromFunction(_ioSeek, _seekFailReturn));
  }

  static final _close = _ffilib.lookupFunction<
      Void Function(Pointer<FFMpegFormatContext>),
      void Function(Pointer<FFMpegFormatContext>)>(
    'FFMpegFormatContext_close',
  );
  Future close() async {
    _close(_this!);
    _this = null;
    await req.close();
    _protocolRequests.remove(identityHashCode(req));
  }

  static final _getDuration = _ffilib.lookupFunction<
      Int64 Function(Pointer<FFMpegFormatContext>),
      int Function(Pointer<FFMpegFormatContext>)>(
    'FFMpegFormatContext_getDuration',
  );
  int getDuration() => _getDuration(_this!);
  static final _seekTo = _ffilib.lookupFunction<
      Int64 Function(
          Pointer<FFMpegFormatContext>, Int64, Int64, Int64, Int64, Int64),
      int Function(Pointer<FFMpegFormatContext>, int, int, int, int, int)>(
    'FFMpegFormatContext_seekTo',
  );
  int seekTo(int ts,
          {int streamIndex = -1,
          int minTs = INT64_MIN,
          int maxTs = INT64_MAX,
          int flags = 0}) =>
      _seekTo(_this!, streamIndex, minTs, ts, maxTs, flags);
  static final _getPacket = _ffilib.lookupFunction<
      Pointer<AVPacket> Function(Pointer<FFMpegFormatContext>),
      Pointer<AVPacket> Function(Pointer<FFMpegFormatContext>)>(
    'FFMpegFormatContext_getPacket',
  );
  Pointer<AVPacket> getPacket() => _getPacket(_this!);

  static final _findStreamsCount = _ffilib.lookupFunction<
      Int64 Function(Pointer<FFMpegFormatContext>),
      int Function(Pointer<FFMpegFormatContext>)>(
    'FFMpegFormatContext_findStreamsCount',
  );
  static final _getStreams = _ffilib.lookupFunction<
      Pointer<Pointer<AVStream>> Function(Pointer<FFMpegFormatContext>),
      Pointer<Pointer<AVStream>> Function(Pointer<FFMpegFormatContext>)>(
    'FFMpegFormatContext_getStreams',
  );
  List<Pointer<AVStream>> getStreams() {
    final nbStreams = _findStreamsCount(_this!);
    if (nbStreams < 0) throw Exception("avformat_find_stream_info failed");
    final _streams = <Pointer<AVStream>>[];
    final streams = _getStreams(_this!);
    for (var i = 0; i < nbStreams; ++i) {
      final stream = streams.elementAt(i).value;
      _streams.add(stream);
    }
    return _streams;
  }
}
