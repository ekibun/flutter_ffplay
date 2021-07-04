import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ffmpeg/ffmpeg.dart';

import 'protocol.dart';

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
    text: 'https://media.w3.org/2010/05/sintel/trailer.mp4',
  );
  FFMpegContext? _ctx;
  Playback? _playback;

  bool _isPlaying = false;
  int _duration = 0;
  int _position = 0;
  bool seeking = false;

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
                    final request = HttpProtocolRequest(Uri.parse(url));
                    final playback = _playback ??= await Playback.create();
                    final ctx = _ctx = FFMpegContext(
                      request,
                      playback,
                      onFrame: (pts) {
                        setState(() {
                          if (pts == null) {
                            _isPlaying = false;
                          } else {
                            _isPlaying = true;
                            _position = seeking ? _position : pts;
                          }
                        });
                      },
                    );
                    final streams = await ctx.getStreams();
                    _duration = await ctx.getDuration();
                    await ctx.play(streams);
                    setState(() {});
                  },
                ),
              ],
            ),
            (_playback?.textureId ?? -1) != -1
                ? Center(
                    child: AspectRatio(
                    aspectRatio: _playback!.aspectRatio,
                    child: Texture(textureId: _playback!.textureId),
                  ))
                : const SizedBox(),
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
                        seeking = true;
                        setState(() {
                          _position = pos.toInt();
                        });
                      },
                      onChangeEnd: (pos) async {
                        await _ctx?.seekTo(pos.toInt());
                        seeking = false;
                      }),
                ),
                Text("${parseHHMMSS(_position)}/${parseHHMMSS(_duration)}"),
                const SizedBox(width: 8),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
