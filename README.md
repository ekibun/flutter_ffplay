# flutter_ffplay

A video player powered by ffmpeg.

## Getting Started

This project is a video player using `ffmpeg`. Currently, plugin supports Android and Windows. It will be appreciated for introducing it to another platforms. 

A fully custom IO interface is provided in this plugin, users can provide their own data stream to ffplay.

### Compile ffmpeg

Before using this plugin, you need to compile ffmpeg first.

For Android, build script use `ANDROID_NDK_HOME` to find the android ndk.

For Windows, You need `msys2` with `msvc`, or build with `mingw64` toolchains in `linux`.

For `msys2`, you should setup `vcvarsall` before call `cxx/build.sh`, For example:

```bat
set MSYS2_PATH_TYPE=inherit
call "D:\Apps\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build\vcvarsall.bat" x64
"D:\Apps\msys64\usr\bin\bash.exe" --login cxx/build.sh
```

### Basical usage

First, You need to create an instance of `IOHandler`. An example of `http` protocol is provded in `example/lib/iohandler.dart`

```dart
final ioHandler = HttpIOHandler();
```

Then, create a `Playback` instance to hold playback information. An `onFrame` callback can be passed here to get the current position:

```dart
final playback = await Playback.create(onFrame: (pts) {
  setState(() {
    if (pts == null) {
      _isPlaying = false;
    } else {
      _isPlaying = true;
      _position = _isSeeking ? _position : pts;
    }
  });
});
```

`Playback` instance has `textureId` and `aspectRatio` parameters for users to create `TextureView`:

```dart
AspectRatio(
  aspectRatio: playback.aspectRatio,
  child: Texture(textureId: playback.textureId),
)
```

After that, it is time to create `FFMpegContext`:

```dart
final ctx = FFMpegContext(url, ioHandler, playback);
```

Then call `getStream` to get infomation of `FFMpegContext`:

```dart
final streams = await ctx.getStreams();
```

Finally, call `play` with a list of `FFMpegStream` to play.

```dart
await ctx.play(streams);
```

## Intergrate into other platforms

Interaction between `dart` and `ffmpeg` are achieved by `ffi` except the playback. To intergrate this plugin to other platforms, you should compile `cxx/ffi.cpp` with your platform code and add the library path to `ffi.dart`. Then, you also need to implement the playback by realize the `flutter_ffplay` method channel.