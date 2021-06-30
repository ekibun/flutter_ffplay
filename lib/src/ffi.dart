import 'dart:ffi';

import 'dart:io';

const AVSEEK_SIZE = 0x10000;
const AVSEEK_FORCE = 0x20000;

const INT64_MIN = -0x8000000000000000;
const INT64_MAX = 0x7fffffffffffffff;

const AV_TIME_BASE = 1000000;

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

final ffilib = Platform.environment['FLUTTER_TEST'] == 'true'
    ? DynamicLibrary.open('./test/build/Debug/player_plugin.dll')
    : DynamicLibrary.open('player_plugin.dll');

Map<String, Function> _ffiCache = {};
int _ffiClassGet<C extends Opaque>(Pointer<C> obj, String propName) =>
    _ffiClassMethod(obj, 'get_$propName');
int _ffiClassMethod<C extends Opaque>(Pointer<C> obj, String method) {
  final ffiMethodName = '${C}_$method';
  final cache = _ffiCache[ffiMethodName] ??=
      ffilib.lookupFunction<Int64 Function(Pointer), int Function(Pointer)>(
          ffiMethodName);
  return cache(obj);
}

class AVFormatContext extends Opaque {}

class AVCodecContext extends Opaque {}

class PlaybackClient extends Opaque {}

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
  int get codecType => _ffiClassGet(this, 'codecType');
  static final _getFramePts = ffilib.lookupFunction<
      Int64 Function(Pointer<AVStream>, Pointer<AVFrame>),
      int Function(Pointer<AVStream>, Pointer<AVFrame>)>(
    'AVStream_getFramePts',
  );
  int getFramePts(Pointer<AVFrame> frame) => _getFramePts(this, frame);
}

extension PointerAVFrame on Pointer<AVFrame> {
  void close() => _ffiClassMethod(this, 'close');
}

extension PointerAVPacket on Pointer<AVPacket> {
  int get streamIndex => _ffiClassGet(this, 'stream_index');
  void close() => _ffiClassMethod(this, 'close');
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

extension PointerPlaybackClient on Pointer<PlaybackClient> {
  static final _postFrame = ffilib.lookupFunction<
      Int64 Function(Int64, Pointer<PlaybackClient>, Pointer<AVFrame>),
      int Function(int, Pointer<PlaybackClient>, Pointer<AVFrame>)>(
    'PlaybackClient_postFrame',
  );
  int postFrame(int codecType, Pointer<AVFrame> packet) =>
      _postFrame(codecType, this, packet);

  Future _waitHalfBuffer() => Future.delayed(
      Duration(milliseconds: _ffiClassGet(this, 'audioBufferDuration') ~/ 2));

  Future<int> flushAudioBuffer() async {
    int padding;
    while ((padding = _ffiClassMethod(this, 'flushAudioBuffer')) < 0) {
      await _waitHalfBuffer();
    }
    return padding - 1;
  }

  void flushVideoBuffer() => _ffiClassMethod(this, 'flushVideoBuffer');

  void start() => _ffiClassMethod(this, 'start');

  void stop() => _ffiClassMethod(this, 'stop');

  close() => _ffiClassMethod(this, 'close');
}

class CodecContext {
  Pointer<AVCodecContext>? _this;

  CodecContext(Pointer<AVStream> stream) {
    _this = Pointer.fromAddress(_ffiClassMethod(stream, 'createCodec'));
    if (_this!.address == 0) throw Exception('AVCodecContext create failed');
  }

  static final _sendPacketAndGetFrame = ffilib.lookupFunction<
      Pointer<AVFrame> Function(Pointer<AVCodecContext>, Pointer<AVPacket>),
      Pointer<AVFrame> Function(Pointer<AVCodecContext>, Pointer<AVPacket>)>(
    'AVCodecContext_sendPacketAndGetFrame',
  );
  Pointer<AVFrame> sendPacketAndGetFrame(Pointer<AVPacket> packet) =>
      _sendPacketAndGetFrame(_this!, packet);

  void close() {
    _ffiClassMethod(_this!, 'close');
    _this = null;
  }

  void flush() => _ffiClassMethod(_this!, 'flush');
}

class FormatContext {
  final ProtocolRequest _req;
  Pointer<AVFormatContext>? _this;
  static final _create = ffilib.lookupFunction<
      Pointer<AVFormatContext> Function(
          IntPtr,
          Int64,
          Pointer<
              NativeFunction<Int32 Function(IntPtr, Pointer<Uint8>, Int32)>>,
          Pointer<NativeFunction<Int64 Function(IntPtr, Int64, Int32)>>),
      Pointer<AVFormatContext> Function(
          int,
          int,
          Pointer<
              NativeFunction<Int32 Function(IntPtr, Pointer<Uint8>, Int32)>>,
          Pointer<NativeFunction<Int64 Function(IntPtr, Int64, Int32)>>)>(
    'AVFormatContext_create',
  );

  FormatContext(this._req) {
    final idReq = identityHashCode(_req);
    _protocolRequests[idReq] = _req;
    _this = _create(
        idReq,
        _req.bufferSize,
        Pointer.fromFunction(_ioReadPacket, _readFailReturn),
        Pointer.fromFunction(_ioSeek, _seekFailReturn));
    if (_this!.address == 0) throw Exception('AVFormatContext create failed');
  }

  static final _close = ffilib.lookupFunction<
      Void Function(Pointer<AVFormatContext>),
      void Function(Pointer<AVFormatContext>)>(
    'AVFormatContext_close',
  );
  Future close() async {
    _close(_this!);
    _this = null;
    await _req.close();
    _protocolRequests.remove(identityHashCode(_req));
  }

  int getDuration() => _ffiClassGet(_this!, 'duration');

  static final _seekTo = ffilib.lookupFunction<
      Int64 Function(
          Pointer<AVFormatContext>, Int64, Int64, Int64, Int64, Int64),
      int Function(Pointer<AVFormatContext>, int, int, int, int, int)>(
    'AVFormatContext_seekTo',
  );
  int seekTo(int ts,
          {int streamIndex = -1,
          int minTs = INT64_MIN,
          int maxTs = INT64_MAX,
          int flags = 0}) =>
      _seekTo(_this!, streamIndex, minTs, ts, maxTs, flags);

  static final _getPacket = ffilib.lookupFunction<
      Int64 Function(Pointer<AVFormatContext>, Pointer<Pointer<AVPacket>>),
      int Function(Pointer<AVFormatContext>, Pointer<Pointer<AVPacket>>)>(
    'AVFormatContext_getPacket',
  );
  int getPacket(Pointer<Pointer<AVPacket>> packet) =>
      _getPacket(_this!, packet);

  List<Pointer<AVStream>> getStreams() {
    final nbStreams = _ffiClassMethod(_this!, 'findStreamCount');
    if (nbStreams < 0) throw Exception("avformat_find_stream_info failed");
    final _streams = <Pointer<AVStream>>[];
    final streams =
        Pointer<Pointer<AVStream>>.fromAddress(_ffiClassGet(_this!, 'streams'));
    for (var i = 0; i < nbStreams; ++i) {
      final stream = streams.elementAt(i).value;
      _streams.add(stream);
    }
    return _streams;
  }
}
