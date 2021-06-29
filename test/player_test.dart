// @dart=2.9
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/executable.dart';
import 'package:flutter_tools/src/windows/visual_studio.dart';
import 'package:file/local.dart';
import 'package:player/src/ffi.dart';
import 'package:process/process.dart';

void main() {
  test('make', () async {
    final platform = LocalPlatform();
    final utf8Encoding = Encoding.getByName('utf-8');
    String cmakePath = 'cmake';
    if (platform.isWindows) {
      final stdio = Stdio();
      final vs = VisualStudio(
          fileSystem: LocalFileSystem(),
          processManager: LocalProcessManager(),
          platform: platform,
          logger: LoggerFactory(
            stdio: stdio,
            terminal: AnsiTerminal(
              stdio: stdio,
              platform: platform,
            ),
            outputPreferences: OutputPreferences(
              wrapText: stdio.hasTerminal,
              showColor: platform.stdoutSupportsAnsi,
              stdio: stdio,
            ),
          ).createLogger(
              verbose: false,
              prefixedErrors: false,
              machine: false,
              daemon: false,
              windows: platform.isWindows));
      cmakePath = vs.cmakePath;
    }
    final buildDir = './build';
    var result = Process.runSync(
      cmakePath,
      ['-S', './', '-B', buildDir],
      workingDirectory: 'test',
      stdoutEncoding: utf8Encoding,
      stderrEncoding: utf8Encoding,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    expect(result.exitCode, 0);

    result = Process.runSync(
      cmakePath,
      ['--build', buildDir, '--verbose'],
      workingDirectory: 'test',
      stdoutEncoding: utf8Encoding,
      stderrEncoding: utf8Encoding,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    expect(result.exitCode, 0);
  });
  test('get stream info', () async {
    final url = 'D:/CloudMusic/seven oops - オレンジ.flac';
    final protocol = await FileRequest.open(url);
    final ctx = FormatContext(protocol);
    print(ctx.getStreams().length);
  });
}

class FileRequest extends ProtocolRequest {
  RandomAccessFile file;

  FileRequest._new(this.file, [int bufferSize = 32768]) : super(bufferSize);

  static Future<FileRequest> open(String url) async {
    return FileRequest._new(await File(url).open());
  }

  @override
  Future close() async {
    await file.close();
    file = null;
  }

  @override
  int read(Pointer<Uint8> buf, int size) {
    final ret = file.readIntoSync(buf.asTypedList(size));
    if (ret == 0) return -1;
    return ret;
  }

  @override
  int seek(int offset, int whence) {
    switch (whence) {
      case AVSEEK_SIZE:
        return file.lengthSync();
      default:
        file.setPositionSync(offset);
        return 0;
    }
  }
}
