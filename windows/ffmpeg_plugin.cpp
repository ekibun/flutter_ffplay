#include "include/ffmpeg/ffmpeg_plugin.h"
#include "flutter_video_renderer.hpp"

namespace
{

  class FfmpegPlugin : public flutter::Plugin
  {
  public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

    FfmpegPlugin(
        flutter::PluginRegistrarWindows *registrar,
        std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel);

    virtual ~FfmpegPlugin();

  private:
    // Called when a method is called on this plugin's channel from Dart.
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue> &method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
    flutter::BinaryMessenger *messenger_;
    flutter::TextureRegistrar *textures_;
  };

  inline int64_t getIntVariant(const flutter::EncodableValue &data)
  {
    if (std::holds_alternative<int32_t>(data))
      return std::get<int32_t>(data);
    return std::get<int64_t>(data);
  }

  // static
  void FfmpegPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "flutter_ffplay",
            &flutter::StandardMethodCodec::GetInstance());

    auto *channel_pointer = channel.get();

    auto plugin = std::make_unique<FfmpegPlugin>(registrar, std::move(channel));

    channel_pointer->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  FfmpegPlugin::FfmpegPlugin(
      flutter::PluginRegistrarWindows *registrar,
      std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel)
      : channel_(std::move(channel)),
        messenger_(registrar->messenger()),
        textures_(registrar->texture_registrar()) {}

  FfmpegPlugin::~FfmpegPlugin() {}

  void FfmpegPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    if (method_call.method_name().compare("create") == 0)
    {
      auto renderer = new FlutterVideoRenderer(textures_);
      result->Success(
          flutter::EncodableMap{
              {"ctx", (int64_t)renderer},
              {"textureId", renderer->texture_id()},
              {"audioBufferTime", renderer->audioBufferFrameSize * 1000 / renderer->sampleRate},
              {"sampleRate", renderer->sampleRate},
              {"channels", renderer->channels},
              {"audioFormat", renderer->audioFormat},
              {"videoFormat", AV_PIX_FMT_RGBA}});
      return;
    }
    auto pargs = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (pargs == nullptr)
    {
      result->Error("flushVideoBuffer", "Invalid arguments");
      return;
    };
    auto args = (*pargs);
    auto ctx = (FlutterVideoRenderer *)getIntVariant(args[flutter::EncodableValue("ctx")]);
    if (method_call.method_name().compare("flushAudioBuffer") == 0)
    {
      auto buffer = (uint8_t *)getIntVariant(args[flutter::EncodableValue("buffer")]);
      auto length = getIntVariant(args[flutter::EncodableValue("length")]);
      result->Success(ctx->flushAudioBuffer(buffer, length));
    }
    else if (method_call.method_name().compare("flushVideoBuffer") == 0)
    {
      auto buffer = (uint8_t *)getIntVariant(args[flutter::EncodableValue("buffer")]);
      auto width = getIntVariant(args[flutter::EncodableValue("width")]);
      auto height = getIntVariant(args[flutter::EncodableValue("height")]);
      ctx->flushVideoBuffer(buffer, width, height);
      result->Success();
    }
    else if (method_call.method_name().compare("pause") == 0)
    {
      result->Success(ctx->pause());
    }
    else if (method_call.method_name().compare("resume") == 0)
    {
      result->Success(ctx->resume());
    }
    else if (method_call.method_name().compare("stop") == 0)
    {
      result->Success(ctx->stop());
    }
    else if (method_call.method_name().compare("close") == 0)
    {
      delete ctx;
      result->Success();
    }
    else
    {
      result->NotImplemented();
    }
  }

} // namespace

void FfmpegPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar)
{
  FfmpegPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
