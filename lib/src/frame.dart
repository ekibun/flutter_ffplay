part of '../ffmpeg.dart';

class FFMpegFrame {
  int timestamp = -1;
  _PTS? _processing;
  Pointer<ffi.AVFrame>? _p;
  FFMpegFrame._(this._p);

  void _close() {
    _p?.close();
    _p = null;
  }
}
