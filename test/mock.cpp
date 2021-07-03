#ifdef _MSC_VER
#define DLLEXPORT __declspec(dllexport)
#include "../windows/audio.hpp"
#else
#define DLLEXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#define MOCKMETHOD(m) DLLEXPORT int64_t Mock_##m(AudioClientImpl *ctx) { return ctx->m(); }

struct _PlaybackCtx
{
  int64_t sampleRate;
  int64_t channels;
  int64_t audioFormat;
  int64_t bufferFrameCount;
  AudioClientImpl *ctx;
};

extern "C"
{
  DLLEXPORT _PlaybackCtx Mock_createPlayback()
  {
    auto audio = new AudioClientImpl();
    return {
        audio->sampleRate,
        audio->channels,
        audio->audioFormat,
        audio->bufferFrameCount,
        audio};
  }

  DLLEXPORT int64_t Mock_audioWriteBuffer(
      AudioClientImpl *ctx, uint8_t *data, int64_t length)
  {
    return ctx->flushAudioBuffer(data, length);
  }

  MOCKMETHOD(pause)
  MOCKMETHOD(resume)
  MOCKMETHOD(stop)
  MOCKMETHOD(getCurrentPadding)

}