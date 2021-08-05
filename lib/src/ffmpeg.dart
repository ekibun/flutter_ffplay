part of '../flutter_ffplay.dart';

class _PTS {
  int _relate = 0;
  int _absolute = DateTime.now().millisecondsSinceEpoch;
  bool playing = false;
  final Map<int, FFMpegStream> streams;
  _PTS(this.streams, [this._relate = 0]);

  void update(int relate) {
    _relate = relate;
    _absolute = DateTime.now().millisecondsSinceEpoch;
  }

  int ptsNow() =>
      (DateTime.now().millisecondsSinceEpoch - _absolute) *
          ffi.AV_TIME_BASE ~/
          1000 +
      _relate;
}

class FFMpegContext extends FormatContext {
  final Playback? _playback;

  FFMpegContext(String url, IOHandler ioHandler, this._playback)
      : super(url, ioHandler);
  _PTS? _pts;
  Future? _playingFuture;

  Future play(List<FFMpegStream> streams) async {
    final _streams = <int, FFMpegStream>{};
    final vstream =
        streams.indexWhere((s) => s.codecType == ffi.AVMediaType.VIDEO);
    if (vstream >= 0) _streams[ffi.AVMediaType.VIDEO] = streams[vstream];
    final astream =
        streams.indexWhere((s) => s.codecType == ffi.AVMediaType.AUDIO);
    if (astream >= 0) _streams[ffi.AVMediaType.AUDIO] = streams[astream];
    await pause();
    _pts = _PTS(_streams);
    _pts!.playing = true;
    return seekTo(0);
  }

  Future waitToStop() async => _playingFuture;

  Future pause() async {
    _pts?.playing = false;
    await _playback?.pause();
    return Future.value(_playingFuture);
  }

  final _codecs = <int, CodecContext>{};
  final _frames = <int, List<FFMpegFrame>>{};

  @override
  Future close() async {
    await pause();
    await super.close();
    final codecFinals = [..._codecs.values].map((codec) => codec.close());
    _codecs.clear();
    await Future.wait(codecFinals);
  }

  @override
  Future seekTo(
    int ts, {
    int streamIndex = -1,
    int minTs = ffi.INT64_MIN,
    int maxTs = ffi.INT64_MAX,
    int flags = 0,
  }) async {
    if (_pts == null) throw Exception("no pts data");
    final pauseAtSeekTo = _pts!.playing;
    final pts = _PTS(_pts!.streams, ts);
    _pts = pts;
    // remove cache frame
    for (var frames in _frames.values) {
      for (var frame in frames) {
        frame._close();
      }
      frames.clear();
    }
    _frames.clear();
    // flush codec
    for (final codec in _codecs.values) {
      await codec.flush();
    }
    await _playback?.stop();
    // seek
    await super.seekTo(
      ts,
      streamIndex: streamIndex,
      minTs: minTs,
      maxTs: maxTs,
      flags: flags,
    );
    // seek to next frame
    if (pts.streams[ffi.AVMediaType.VIDEO] != null) {
      Completer<bool> ret = Completer();
      _playingFuture = _resume(ret);
      return ret.future.then((hitframe) {
        if (hitframe && !pauseAtSeekTo) pause();
      });
    } else if (pauseAtSeekTo) {
      _playingFuture = resume();
    }
  }

  Future resume() => _resume(null);

  Future _resume(Completer<bool>? onNextFrame) async {
    final pts = _pts;
    if (pts == null) return;
    bool _isPlaying() => _pts == pts && pts.playing;
    try {
      pts.playing = true;
      await _playback?.resume();
      final streams = pts.streams.values.toList();
      pts.streams.forEach((codecType, stream) async {
        Future? lastUpdate;
        while (true) {
          if (!_isPlaying()) break;
          final frame = _frames[codecType]?.firstWhere(
              (f) => f._processing != pts,
              orElse: () => FFMpegFrame._(null));
          if (frame == null || frame._p == null) {
            await Future.delayed(const Duration(milliseconds: 1));
            continue;
          }
          frame._processing = pts;
          final _lastUpdate = lastUpdate;
          lastUpdate = (() async {
            if (!_isPlaying()) return;
            bool muteOnNextFrame() =>
                codecType == ffi.AVMediaType.AUDIO &&
                onNextFrame?.isCompleted == false;
            // decode frame
            if (!muteOnNextFrame()) _playback?._postFrame(codecType, frame);
            await _lastUpdate;
            if (!_isPlaying()) return;
            if (onNextFrame?.isCompleted != false) {
              // wait video
              while (codecType == ffi.AVMediaType.VIDEO &&
                  frame.timestamp > pts.ptsNow()) {
                await Future.delayed(const Duration(milliseconds: 1));
                if (!_isPlaying()) return;
              }
            }
            if (muteOnNextFrame()) return;
            int timestamp =
                await _playback?._flushFrame(codecType, frame) ?? -1;
            if (!_isPlaying()) return;
            if (timestamp >= 0) pts.update(timestamp);
            if (codecType == ffi.AVMediaType.VIDEO &&
                onNextFrame?.isCompleted == false) {
              pts.update(frame.timestamp);
              onNextFrame?.complete(true);
            }
            _playback?._onFrame?.call(pts.ptsNow());
          })()
            ..whenComplete(() {
              _frames[codecType]?.remove(frame);
              frame._close();
            });
          await Future.value(_lastUpdate);
        }
      });
      var sendingPacket = 0;
      while (true) {
        if (!_isPlaying()) break;
        if (sendingPacket > 10 ||
            _frames.values.fold<int>(0, (sum, a) => sum + a.length) > 100) {
          await Future.delayed(const Duration(milliseconds: 1));
          continue;
        }
        final packet = await super.getPacket(streams);
        if (packet.address == 0) {
          if (_frames.values.fold<int>(0, (sum, a) => sum + a.length) == 0) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 100));
          continue;
        }
        if (_pts != pts) {
          packet.close();
          break;
        }
        sendingPacket++;
        final streamIndex = packet.streamIndex;
        final stream =
            pts.streams.values.firstWhere((s) => s.index == streamIndex);
        final codecType = stream.codecType;
        (_codecs[codecType] ??= CodecContext(stream))
            .sendPacketAndGetFrame(packet)
            .then((frame) {
          packet.close();
          sendingPacket--;
          if (frame == null) return;
          if (_pts != pts) {
            frame._close();
            return;
          }
          frame.timestamp = stream._p.getFramePts(frame._p!);
          (_frames[codecType] ??= []).add(frame);
        });
      }
    } finally {
      _playback?._onFrame?.call(null);
      if (onNextFrame?.isCompleted == false) onNextFrame?.complete(false);
      pts.playing = false;
    }
  }
}
