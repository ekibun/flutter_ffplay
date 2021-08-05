import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_ffplay/flutter_ffplay.dart';

import 'iohandler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final TextEditingController _controller = TextEditingController(
    text: 'https://cctvksh5ca.v.kcdnvip.com/clive/cctv1_2/index.m3u8',
  );
  FFMpegContext? _ctx;
  Playback? _playback;
  final ioHandler = HttpIOHandler();

  bool _isPlaying = false;
  int _duration = 0;
  int _position = 0;
  bool _isSeeking = false;

  String parseHHMMSS(int pts) {
    final sec = pts ~/ AV_TIME_BASE;
    final min = sec ~/ 60;
    final hour = min ~/ 60;
    String ret = (min % 60).toString().padLeft(2, '0') +
        ':' +
        (sec % 60).toString().padLeft(2, '0');
    if (hour == 0) return ret;
    return '$hour:$ret';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        type: MaterialType.canvas,
        child: SafeArea(
          child: Column(children: [
            Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                  ),
                ),
                TextButton(
                  child: const Text("load"),
                  onPressed: () async {
                    if (_ctx != null) {
                      final ctx = _ctx;
                      _ctx = null;
                      await ctx?.close();
                    }
                    final url = _controller.text;
                    final playback =
                        _playback ??= await Playback.create(onFrame: (pts) {
                      setState(() {
                        if (pts == null) {
                          _isPlaying = false;
                        } else {
                          _isPlaying = true;
                          _position = _isSeeking ? _position : pts;
                        }
                      });
                    });
                    final ctx = _ctx = FFMpegContext(
                      url,
                      ioHandler,
                      playback,
                    );
                    final streams = await ctx.getStreams();
                    _duration = await ctx.getDuration();
                    await ctx.play(streams);
                    setState(() {});
                  },
                ),
              ],
            ),
            Expanded(
                child: (_playback?.textureId ?? -1) != -1
                    ? Center(
                        child: AspectRatio(
                        aspectRatio: _playback!.aspectRatio,
                        child: Texture(textureId: _playback!.textureId),
                      ))
                    : const SizedBox()),
            Row(
              children: [
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () async {
                    _isPlaying ? _ctx?.pause() : _ctx?.resume();
                  },
                ),
                Expanded(
                  child: Slider(
                      value: max(
                          0, min(_position.toDouble(), _duration.toDouble())),
                      max: max(0, _duration.toDouble()),
                      onChanged: (pos) {
                        _isSeeking = true;
                        setState(() {
                          _position = pos.toInt();
                        });
                      },
                      onChangeEnd: (pos) async {
                        await _ctx?.seekTo(pos.toInt());
                        _isSeeking = false;
                      }),
                ),
                Text(_duration < 0
                    ? parseHHMMSS(_position)
                    : "${parseHHMMSS(_position)}/${parseHHMMSS(_duration)}"),
                const SizedBox(width: 8),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
