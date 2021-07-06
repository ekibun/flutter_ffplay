// @dart=2.9
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tools/src/base/io.dart';
import 'package:flutter_tools/src/base/terminal.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/executable.dart';
import 'package:flutter_tools/src/windows/visual_studio.dart';
import 'package:file/local.dart';
import 'package:flutter_ffplay/ffmpeg.dart';
import 'package:process/process.dart';

// ignore: avoid_relative_lib_imports
import '../example/lib/protocol.dart';
import 'mock.dart';

void main() {
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
    const url = 'http://playertest.longtailvideo.com/adaptive/bipbop/gear4/prog_index.m3u8';
    final ioHandler = HttpIOHandler();
    final ctx = FFMpegContext(url, ioHandler, MockPlayback());
    final streams = await ctx.getStreams();
    // ignore: avoid_print
    print(streams);
    await ctx
        .play(streams.where((s) => s.codecType == AVMediaType.AUDIO).toList());
    await Future.delayed(const Duration(seconds: 5));
    await ctx.seekTo(30 * AV_TIME_BASE);
    await Future.delayed(const Duration(seconds: 30));
  }, timeout: Timeout.none);
}
