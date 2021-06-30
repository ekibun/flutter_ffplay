part of '../ffmpeg.dart';

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
  final Playback _playback;
  FFMpegContext(ProtocolRequest req, this._playback) : super(req);
  _PTS? _pts;
  Future? _playingFuture;

  Future play(List<FFMpegStream> streams) async {
    await pause();
    _pts =
        _PTS(Map.fromEntries(streams.map((s) => MapEntry(s.codecType, s))), 0);
    _pts!.playing = true;
    return seekTo(0);
  }

  Future pause() {
    _pts?.playing = false;
    return Future.value(_playingFuture);
  }

  final _codecs = <int, CodecContext>{};
  final _frames = <int, List<FFMpegFrame>>{};

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
      for (var frame in frames) frame._close();
      frames.clear();
    }
    _frames.clear();
    // flush codec
    for (final codec in _codecs.values) {
      await codec.flush();
    }
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
      Completer ret = Completer();
      _playingFuture = _resume(ret);
      return ret.future;
    } else if (pauseAtSeekTo) {
      _playingFuture = resume();
    }
  }

  Future resume() => _resume(null);

  Future _resume(Completer? onNextFrame) async {
    final pts = _pts!;
    final _isPlaying = () {
      return (_pts == pts) && pts.playing;
    };
    try {
      pts.playing = true;
      final streams = pts.streams.values.toList();
      pts.streams.forEach((codecType, stream) async {
        Future? lastUpdate;
        while (true) {
          await Future.delayed(Duration(milliseconds: 1));
          if (!_isPlaying()) break;
          final frame = _frames[codecType]?.firstWhere(
              (f) => f._processing != pts,
              orElse: () => FFMpegFrame._(null));
          if (frame == null || frame._p == null) continue;
          frame._processing = pts;
          final _lastUpdate = lastUpdate;
          final ptsNow = pts.ptsNow();
          lastUpdate = (() async {
            if ((onNextFrame?.isCompleted == false ||
                    codecType == ffi.AVMediaType.VIDEO) &&
                frame._pts > ptsNow)
              await Future.delayed(Duration(
                  milliseconds:
                      (frame._pts - ptsNow) * 1000 ~/ ffi.AV_TIME_BASE));
            if (!_isPlaying() ||
                (onNextFrame?.isCompleted == false &&
                    codecType == ffi.AVMediaType.AUDIO)) return;
            _playback._postFrame(codecType, frame);
            await _lastUpdate;
            if (!_isPlaying()) return;
            int timestamp = await _playback._flushFrame(codecType, frame);
            if (!_isPlaying()) return;
            if (timestamp >= 0) pts.update(timestamp);
            if (codecType == ffi.AVMediaType.VIDEO &&
                onNextFrame?.isCompleted == false) onNextFrame?.complete();
            _frames.remove(frame);
            frame._close();
          })();
          await Future.value(_lastUpdate);
        }
      });
      var lastDecoTimeStamp = -1;
      while (true) {
        await Future.delayed(Duration(milliseconds: 1));
        if (!_isPlaying()) break;
        if (lastDecoTimeStamp - pts.ptsNow() > 1 * ffi.AV_TIME_BASE) continue;
        final packet = await super.getPacket(streams);
        if (packet.address == 0) break;
        if (this._pts != pts) {
          packet.close();
          break;
        }
        final streamIndex = packet.streamIndex;
        final stream =
            pts.streams.values.firstWhere((s) => s.index == streamIndex);
        final codecType = stream.codecType;
        (_codecs[codecType] ??= CodecContext(stream))
            .sendPacketAndGetFrame(packet)
            .then((frame) {
          packet.close();
          if (frame == null) return;
          if (this._pts != pts) {
            frame._close();
            return;
          }
          frame._pts = stream._p.getFramePts(frame._p!);
          lastDecoTimeStamp = frame._pts;
          (_frames[codecType] ??= []).add(frame);
        });
      }
    } finally {
      // _onFrame?.call(null);
      if (onNextFrame?.isCompleted == false) onNextFrame?.complete();
      pts.playing = false;
    }
  }
}
