#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include "audio.hpp"
#include <mutex>

class FlutterVideoRenderer : public AudioClientImpl
{
  std::shared_ptr<FlutterDesktopPixelBuffer> pixel_buffer;
  mutable std::shared_ptr<uint8_t> rgb_buffer;

public:
  FlutterVideoRenderer(flutter::TextureRegistrar *registrar)
      : registrar_(registrar)
  {
    texture_ =
        std::make_unique<flutter::TextureVariant>(flutter::PixelBufferTexture(
            [this](size_t width,
                   size_t height) -> const FlutterDesktopPixelBuffer * {
              return this->CopyPixelBuffer(width, height);
            }));

    texture_id_ = registrar_->RegisterTexture(texture_.get());
  }

  void flushVideoBuffer(uint8_t *buffer, int width, int height)
  {
    if (!pixel_buffer.get())
    {
      pixel_buffer.reset(new FlutterDesktopPixelBuffer());
    }
    if (pixel_buffer->width != width ||
        pixel_buffer->height != height)
    {
      pixel_buffer->width = width;
      pixel_buffer->height = height;
      pixel_buffer->buffer = buffer;
    }
    registrar_->MarkTextureFrameAvailable(texture_id_);
  }

  ~FlutterVideoRenderer()
  {
    registrar_->UnregisterTexture(texture_id_);
  }

  FlutterDesktopPixelBuffer *CopyPixelBuffer(
      size_t width,
      size_t height)
  {
    return pixel_buffer.get();
  };

  int64_t texture_id() { return texture_id_; }

private:
  flutter::TextureRegistrar *registrar_ = nullptr;
  int64_t texture_id_ = -1;
  std::unique_ptr<flutter::TextureVariant> texture_;
  mutable std::mutex mutex_;
};