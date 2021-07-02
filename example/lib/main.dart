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
    text: 'D:/Downloads/System/big_buck_bunny_2.mp4',
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
                  final request = await FileRequest.open(url);
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
          Expanded(
            child: _playback != null
                ? Texture(textureId: _playback!.textureId)
                : const SizedBox(),
          ),
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
                    value:
                        max(0, min(_position.toDouble(), _duration.toDouble())),
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
    );
  }
}
