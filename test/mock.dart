import 'dart:ffi';
import 'package:player/src/ffi.dart';

final createMockPlayback = ffilib.lookupFunction<
    Pointer<PlaybackClient> Function(), Pointer<PlaybackClient> Function()>(
  'Mock_createPlayback',
);