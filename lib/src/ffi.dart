// ignore_for_file: constant_identifier_names

import 'dart:ffi';

import 'dart:io';

import 'package:ffi/ffi.dart';

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

final _ffilib = (() {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    return DynamicLibrary.open('./test/build/Debug/flutter_ffplay_plugin.dll');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('flutter_ffplay_plugin.dll');
  } else if (Platform.isAndroid) {
    return DynamicLibrary.open('libffmpeg.so');
  }
  return DynamicLibrary.process();
})();

Map<String, Function> _ffiCache = {};
int _ffiClassGet<C extends NativeType>(Pointer<C> obj, String propName) =>
    _ffiClassMethod(obj, 'get_$propName');
int _ffiClassMethod<C extends NativeType>(Pointer<C> obj, String method) {
  final ffiMethodName = '${C}_$method';
  final cache = _ffiCache[ffiMethodName] ??=
      _ffilib.lookupFunction<Int64 Function(Pointer), int Function(Pointer)>(
          ffiMethodName);
  return cache(obj);
}

class AVFormatContext extends Opaque {}

class AVCodecContext extends Opaque {}

class AVIOContext extends Opaque {}

class SWContext extends Struct {
  @Double()
  external double speedRatio;
  @Int64()
  external int sampleRate;
  @Int64()
  external int channels;
  @Int64()
  external int audioFormat;
  external Pointer<Uint8> audioBuffer;
  @Int64()
  external int audioBufferSize;
  @Int64()
  external int width;
  @Int64()
  external int height;
  @Int64()
  external int videoFormat;
  external Pointer<Uint8> videoBuffer;
  @Int64()
  external int videoBufferSize;
}

final int _sizeOfSWContext = _ffilib
    .lookupFunction<Int64 Function(), int Function()>('sizeOfSWContext')();

Pointer<T> mallocz<T extends NativeType>(int bytes) {
  final ptr = malloc<Uint8>(bytes);
  ptr.asTypedList(bytes).setAll(0, List.filled(bytes, 0));
  return ptr.cast();
}

Pointer<SWContext> mallocSWContext() => mallocz<SWContext>(_sizeOfSWContext);

extension PointerSWContext on Pointer<SWContext> {
  static final _postFrame = _ffilib.lookupFunction<
      Int64 Function(Int64, Pointer<SWContext>, Pointer<AVFrame>),
      int Function(int, Pointer<SWContext>, Pointer<AVFrame>)>(
    'SWContext_postFrame',
  );
  int postFrame(int codecType, Pointer<AVFrame> packet) =>
      _postFrame(codecType, this, packet);

  // Future _waitHalfBuffer() => Future.delayed(
  //     Duration(milliseconds: _ffiClassGet(this, 'audioBufferDuration') ~/ 2));

  // Future<int> flushAudioBuffer() async {
  //   int padding;
  //   while ((padding = _ffiClassMethod(this, 'flushAudioBuffer')) < 0) {
  //     await _waitHalfBuffer();
  //   }
  //   return padding - 1;
  // }
}

class AVPacket extends Opaque {}

class AVStream extends Opaque {}

class AVFrame extends Opaque {}

abstract class IOContext {
  final int bufferSize;
  int open(String url);
  int close(int ctx);
  int read(int id, Pointer<Uint8> buf, int size);
  int seek(int id, int offset, int whence);
  IOContext(
    this.bufferSize,
  );
}

extension PointerAVStream on Pointer<AVStream> {
  int get codecType => _ffiClassGet(this, 'codecType');
  static final _getFramePts = _ffilib.lookupFunction<
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

class CodecContext {
  Pointer<AVCodecContext>? _this;

  CodecContext(Pointer<AVStream> stream) {
    _this = Pointer.fromAddress(_ffiClassMethod(stream, 'createCodec'));
    if (_this!.address == 0) throw Exception('AVCodecContext create failed');
  }

  static final _sendPacketAndGetFrame = _ffilib.lookupFunction<
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

final _ioContextCreate = _ffilib.lookupFunction<
    Pointer<AVIOContext> Function(
        IntPtr,
        Int64,
        Pointer<NativeFunction<Int32 Function(IntPtr, Pointer<Uint8>, Int32)>>,
        Pointer<NativeFunction<Int64 Function(IntPtr, Int64, Int32)>>),
    Pointer<AVIOContext> Function(
        int,
        int,
        Pointer<NativeFunction<Int32 Function(IntPtr, Pointer<Uint8>, Int32)>>,
        Pointer<NativeFunction<Int64 Function(IntPtr, Int64, Int32)>>)>(
  'AVIOContext_create',
);

final Map<int, FormatContext> _pointerToContext = {};
final Map<int, FormatContext> _keyToContext = {};
final Map<int, int> _pointerToKey = {};
const _ffiFailReturn = -1;
int _ioOpen(Pointer<AVFormatContext> s, Pointer<Pointer<AVIOContext>> pb,
    Pointer<Utf8> url, int flag, Pointer options) {
  final urlStr = url.toDartString();
  final format = _pointerToContext[s.address];
  final key = format!._io.open(urlStr);
  final ctx = _ioContextCreate(
      key,
      format._io.bufferSize,
      Pointer.fromFunction(_ioReadPacket, _ffiFailReturn),
      Pointer.fromFunction(_ioSeek, _ffiFailReturn));
  _keyToContext[key] = format;
  _pointerToKey[ctx.address] = key;
  pb.value = ctx;
  return 0;
}

int _ioClose(Pointer<AVFormatContext> s, Pointer<AVIOContext> pb) {
  final key = _pointerToKey.remove(pb.address)!;
  return _keyToContext.remove(key)!._io.close(key);
}

int _ioReadPacket(int opaque, Pointer<Uint8> buf, int bufSize) {
  return _keyToContext[opaque]!._io.read(opaque, buf, bufSize);
}

int _ioSeek(int opaque, int offset, int whence) {
  return _keyToContext[opaque]!._io.seek(opaque, offset, whence);
}

class FormatContext {
  final IOContext _io;
  Pointer<AVFormatContext>? _this;
  static final _create = _ffilib.lookupFunction<
      Pointer<AVFormatContext> Function(
          Pointer<
              NativeFunction<
                  IntPtr Function(
                      Pointer<AVFormatContext>,
                      Pointer<Pointer<AVIOContext>>,
                      Pointer<Utf8>,
                      IntPtr,
                      Pointer)>>,
          Pointer<
              NativeFunction<
                  IntPtr Function(
                      Pointer<AVFormatContext>, Pointer<AVIOContext>)>>),
      Pointer<AVFormatContext> Function(
          Pointer<
              NativeFunction<
                  IntPtr Function(
                      Pointer<AVFormatContext>,
                      Pointer<Pointer<AVIOContext>>,
                      Pointer<Utf8>,
                      IntPtr,
                      Pointer)>>,
          Pointer<
              NativeFunction<
                  IntPtr Function(
                      Pointer<AVFormatContext>, Pointer<AVIOContext>)>>)>(
    'AVFormatContext_create',
  );

  FormatContext(String url, this._io) {
    final __this = _this = _create(
        Pointer.fromFunction(_ioOpen, _ffiFailReturn),
        Pointer.fromFunction(_ioClose, _ffiFailReturn));
    if (__this.address == 0) throw Exception('AVFormatContext create failed');
    _pointerToContext[__this.address] = this;
    final ret = _open(__this, url.toNativeUtf8());
    if (ret < 0) {
      _this = null;
      _pointerToContext.remove(__this.address);
      throw Exception('AVFormatContext open failed: $ret');
    }
  }

  static final _open = _ffilib.lookupFunction<
      Int64 Function(Pointer<AVFormatContext>, Pointer<Utf8>),
      int Function(Pointer<AVFormatContext>, Pointer<Utf8>)>(
    'AVFormatContext_open',
  );

  static final _close = _ffilib.lookupFunction<
      Void Function(Pointer<AVFormatContext>),
      void Function(Pointer<AVFormatContext>)>(
    'AVFormatContext_close',
  );
  Future close() async {
    final __this = _this;
    _this = null;
    _pointerToContext.remove(__this);
    _close(__this!);
    _keyToContext.removeWhere((key, value) {
      if (value != this) return false;
      _pointerToKey.removeWhere((k, v) => v == key);
      _io.close(key);
      return true;
    });
  }

  int getDuration() => _ffiClassGet(_this!, 'duration');

  static final _seekTo = _ffilib.lookupFunction<
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

  static final _getPacket = _ffilib.lookupFunction<
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
