package soko.ekibun.ffmpeg

import android.os.Build
import androidx.annotation.NonNull
import androidx.annotation.RequiresApi

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry

/** FlutterFfplayPlugin */
class FlutterFfplayPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var textures: TextureRegistry

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_ffplay")
    textures = flutterPluginBinding.textureRegistry
    channel.setMethodCallHandler(this)
  }

  @RequiresApi(Build.VERSION_CODES.M)
  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    if (call.method == "create") {
      val (key, ctx) = PlaybackImpl.create(textures.createSurfaceTexture())
      result.success(mapOf(
              "ctx" to key,
              "textureId" to ctx.textureId,
              "audioBufferTime" to ctx.audioBufferSize * 1000 / ctx.channels / ctx.sampleRate,
              "sampleRate" to ctx.sampleRate,
              "channels" to ctx.channels,
              "audioFormat" to ctx.audioFormat,
              "videoFormat" to ctx.videoFormat
      ))
      return
    }
    val key = call.argument<Int>("ctx")!!
    if(call.method == "close") {
      PlaybackImpl.close(key)
      result.success(null)
      return
    }
    val ctx = PlaybackImpl.get(key)
    when (call.method) {
      "flushAudioBuffer" -> result.success(ctx.flushAudioBuffer(
              call.argument("buffer")!!,
              call.argument("length")!!))
      "flushVideoBuffer" -> result.success(ctx.flushVideoBuffer(
              call.argument("buffer")!!,
              call.argument("length")!!,
              call.argument("width")!!,
              call.argument("height")!!))
      "pause" -> result.success(ctx.pause())
      "resume" -> result.success(ctx.resume())
      "stop" -> result.success(ctx.stop())
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
