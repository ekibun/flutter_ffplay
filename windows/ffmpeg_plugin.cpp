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
            registrar->messenger(), "ffmpeg",
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
    if (method_call.method_name().compare("createPlayback") == 0)
    {
      auto renderer = new FlutterVideoRenderer(textures_);
      result->Success(flutter::EncodableValue((int64_t)renderer));
    }
    else if (method_call.method_name().compare("getTextureId") == 0)
    {
      auto renderer = (FlutterVideoRenderer *)getIntVariant(*method_call.arguments());
      result->Success(flutter::EncodableValue((int64_t)renderer->texture_id()));
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
