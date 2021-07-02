// @dart=2.9
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/executable.dart';
import 'package:flutter_tools/src/windows/visual_studio.dart';
import 'package:file/local.dart';
import 'package:ffmpeg/ffmpeg.dart';
import 'package:process/process.dart';

// ignore: avoid_relative_lib_imports
import '../example/lib/protocol.dart';
import 'package:ffmpeg/src/ffi.dart';

final createMockPlayback = ffilib.lookupFunction<
    Pointer<PlaybackClient> Function(), Pointer<PlaybackClient> Function()>(
  'Mock_createPlayback',
);

void main() {
  const MethodChannel channel = MethodChannel('ffmpeg');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      if (methodCall.method == 'createPlayback') {
        return createMockPlayback().address;
      }
      return 0;
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });
  test('make', () async {
    const platform = LocalPlatform();
    final utf8Encoding = Encoding.getByName('utf-8');
    String cmakePath = 'cmake';
    if (platform.isWindows) {
      final stdio = Stdio();
      final vs = VisualStudio(
          fileSystem: const LocalFileSystem(),
          processManager: const LocalProcessManager(),
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
    const buildDir = './build';
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
    const url = 'D:/CloudMusic/seven oops - オレンジ.flac';
    final protocol = await FileRequest.open(url);
    final ctx = FFMpegContext(protocol, await Playback.create());
    final streams = await ctx.getStreams();
    // ignore: avoid_print
    print(streams);
    await ctx
        .play(streams.where((s) => s.codecType == AVMediaType.AUDIO).toList());
    await Future.delayed(const Duration(seconds: 5));
    await ctx.seekTo(30 * AV_TIME_BASE);
    await Future.delayed(const Duration(seconds: 30));
  });
}
