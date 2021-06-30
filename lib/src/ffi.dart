import 'dart:ffi';

const AVSEEK_SIZE = 0x10000;
const AVSEEK_FORCE = 0x20000;

const INT64_MIN = -0x8000000000000000;
const INT64_MAX = 0x7fffffffffffffff;

abstract class AVMediaType {
  /// ///< Usually treated as AVMEDIA_TYPE_DATA
  static const int UNKNOWN = -1;
  static const int VIDEO = 0;
  static const int AUDIO = 1;

  /// ///< Opaque data information usually continuous
  static const int DATA = 2;
  static const int SUBTITLE = 3;

  /// ///< Opaque data information usually sparse
  static const int ATTACHMENT = 4;
  static const int NB = 5;
}

final _ffilib = DynamicLibrary.open('./test/build/Debug/player_plugin.dll');

class _AVFormatContext extends Opaque {}

class _AVCodecContext extends Opaque {}

class _AudioClient extends Opaque {}

class AVPacket extends Opaque {}

class AVStream extends Opaque {}

class AVFrame extends Opaque {}

abstract class ProtocolRequest {
  final int bufferSize;
  int read(Pointer<Uint8> buf, int size);
  int seek(int offset, int whence);
  Future close();
  ProtocolRequest(
    this.bufferSize,
  );
}

extension PointerAVStream on Pointer<AVStream> {
  static final _getCodecType = _ffilib.lookupFunction<
      Int64 Function(Pointer<AVStream>), int Function(Pointer<AVStream>)>(
    'AVStream_getCodecType',
  );
  int getCodecType() => _getCodecType(this);
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

class AudioClient {
  Pointer<_AudioClient>? _this;
  static final _create = _ffilib.lookupFunction<
      Pointer<_AudioClient> Function(), Pointer<_AudioClient> Function()>(
    'AudioClient_create',
  );
  AudioClient() {
    _this = _create();
    if (_this!.address == 0) throw Exception('AudioClient create failed');
  }

  static final _getBufferDuration = _ffilib.lookupFunction<
      Int64 Function(Pointer<_AudioClient>),
      int Function(Pointer<_AudioClient>)>(
    'AudioClient_getBufferDuration',
  );
  Future waitHalfBuffer() =>
      Future.delayed(Duration(milliseconds: _getBufferDuration(_this!) ~/ 2));

  static final _flushBuffer = _ffilib.lookupFunction<
      Int64 Function(Pointer<_AudioClient>),
      int Function(Pointer<_AudioClient>)>(
    'AudioClient_flushBuffer',
  );
  Future flushBuffer() async {
    int padding;
    while ((padding = _flushBuffer(_this!)) < 0) {
      await waitHalfBuffer();
    }
    if (padding == 0) throw Exception('AudioClient flush buffer failed');
    return padding - 1;
  }

  static final _start = _ffilib.lookupFunction<
      Void Function(Pointer<_AudioClient>),
      void Function(Pointer<_AudioClient>)>(
    'AudioClient_start',
  );
  start() => _start(_this!);

  static final _stop = _ffilib.lookupFunction<
      Void Function(Pointer<_AudioClient>),
      void Function(Pointer<_AudioClient>)>(
    'AudioClient_stop',
  );
  stop() => _stop(_this!);

  static final _close = _ffilib.lookupFunction<
      Void Function(Pointer<_AudioClient>),
      void Function(Pointer<_AudioClient>)>(
    'AudioClient_close',
  );
  close() {
    _close(_this!);
    _this = null;
  }
}

class AVCodecContext {
  Pointer<_AVCodecContext>? _this;
  static final _create = _ffilib.lookupFunction<
      Pointer<_AVCodecContext> Function(Pointer<AVStream>),
      Pointer<_AVCodecContext> Function(Pointer<AVStream>)>(
    'AVCodecContext_create',
  );
  AVCodecContext(Pointer<AVStream> stream) {
    _this = _create(stream);
    if (_this!.address == 0) throw Exception('AVCodecContext create failed');
  }

  static final _sendPacketAndGetFrame = _ffilib.lookupFunction<
      Pointer<AVFrame> Function(Pointer<_AVCodecContext>, Pointer<AVPacket>),
      Pointer<AVFrame> Function(Pointer<_AVCodecContext>, Pointer<AVPacket>)>(
    'AVCodecContext_sendPacketAndGetFrame',
  );
  Pointer<AVFrame> sendPacketAndGetFrame(Pointer<AVPacket> packet) =>
      _sendPacketAndGetFrame(_this!, packet);

  static final _close = _ffilib.lookupFunction<
      Void Function(Pointer<_AVCodecContext>),
      void Function(Pointer<_AVCodecContext>)>(
    'AVCodecContext_close',
  );
  void close() {
    _close(_this!);
    _this = null;
  }

  static final _flush = _ffilib.lookupFunction<
      Void Function(Pointer<_AVCodecContext>),
      void Function(Pointer<_AVCodecContext>)>(
    'AVCodecContext_flush',
  );
  void flush() => _flush(_this!);
}

class AVFormatContext {
  final ProtocolRequest _req;
  Pointer<_AVFormatContext>? _this;
  static final _create = _ffilib.lookupFunction<
      Pointer<_AVFormatContext> Function(
          IntPtr,
          Int64,
          Pointer<
              NativeFunction<Int32 Function(IntPtr, Pointer<Uint8>, Int32)>>,
          Pointer<NativeFunction<Int64 Function(IntPtr, Int64, Int32)>>),
      Pointer<_AVFormatContext> Function(
          int,
          int,
          Pointer<
              NativeFunction<Int32 Function(IntPtr, Pointer<Uint8>, Int32)>>,
          Pointer<NativeFunction<Int64 Function(IntPtr, Int64, Int32)>>)>(
    'AVFormatContext_create',
  );

  AVFormatContext(this._req) {
    final idReq = identityHashCode(_req);
    _protocolRequests[idReq] = _req;
    _this = _create(
        idReq,
        _req.bufferSize,
        Pointer.fromFunction(_ioReadPacket, _readFailReturn),
        Pointer.fromFunction(_ioSeek, _seekFailReturn));
    if (_this!.address == 0) throw Exception('AVFormatContext create failed');
  }

  static final _close = _ffilib.lookupFunction<
      Void Function(Pointer<_AVFormatContext>),
      void Function(Pointer<_AVFormatContext>)>(
    'AVFormatContext_close',
  );
  Future close() async {
    _close(_this!);
    _this = null;
    await _req.close();
    _protocolRequests.remove(identityHashCode(_req));
  }

  static final _getDuration = _ffilib.lookupFunction<
      Int64 Function(Pointer<_AVFormatContext>),
      int Function(Pointer<_AVFormatContext>)>(
    'AVFormatContext_getDuration',
  );
  int getDuration() => _getDuration(_this!);
  static final _seekTo = _ffilib.lookupFunction<
      Int64 Function(
          Pointer<_AVFormatContext>, Int64, Int64, Int64, Int64, Int64),
      int Function(Pointer<_AVFormatContext>, int, int, int, int, int)>(
    'AVFormatContext_seekTo',
  );
  int seekTo(int ts,
          {int streamIndex = -1,
          int minTs = INT64_MIN,
          int maxTs = INT64_MAX,
          int flags = 0}) =>
      _seekTo(_this!, streamIndex, minTs, ts, maxTs, flags);
  static final _getPacket = _ffilib.lookupFunction<
      Pointer<AVPacket> Function(Pointer<_AVFormatContext>, Pointer<AVPacket>),
      Pointer<AVPacket> Function(Pointer<_AVFormatContext>, Pointer<AVPacket>)>(
    'AVFormatContext_getPacket',
  );
  Pointer<AVPacket> getPacket(Pointer<AVPacket> packet) =>
      _getPacket(_this!, packet);

  static final _findStreamsCount = _ffilib.lookupFunction<
      Int64 Function(Pointer<_AVFormatContext>),
      int Function(Pointer<_AVFormatContext>)>(
    'AVFormatContext_findStreamsCount',
  );
  static final _getStreams = _ffilib.lookupFunction<
      Pointer<Pointer<AVStream>> Function(Pointer<_AVFormatContext>),
      Pointer<Pointer<AVStream>> Function(Pointer<_AVFormatContext>)>(
    'AVFormatContext_getStreams',
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
