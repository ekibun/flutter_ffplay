import 'dart:ffi';
import 'dart:io';

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
  Future<int> read(Pointer<Uint8> buf, int size) async {
    final ret = await file?.readInto(buf.asTypedList(size)) ?? 0;
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
