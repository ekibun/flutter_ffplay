part of '../ffmpeg.dart';

class FFMpegStream implements _IsolateEncodable {
  final int index;
  Pointer<ffi.AVStream> _p;
  FFMpegStream._(this.index, this._p);

  int get codecType => _p.codecType;

  @override
  Map _encode() => {
        #streamIndex: index,
        #streamPtr: _p.address,
      };

  static FFMpegStream? _decode(Map data) {
    if (data.containsKey(#streamPtr))
      return FFMpegStream._(
        data[#streamIndex],
        Pointer.fromAddress(data[#streamPtr]),
      );
    return null;
  }
}
