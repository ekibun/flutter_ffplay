#ifdef _MSC_VER
#define DLLEXPORT __declspec(dllexport)
#else
#define DLLEXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

extern "C"
{
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libswresample/swresample.h"
#include "libswscale/swscale.h"
#include "libavutil/imgutils.h"

  struct RenderFrame
  {
    int64_t width = 0;
    int64_t height = 0;
    uint8_t *buffer1 = nullptr;
    uint8_t *buffer = nullptr;
    uint8_t *data[4];
    int linesize[4];
  };

  class PlaybackClient
  {
  public:
    // audio
    SwrContext *_swrCtx = nullptr;
    int64_t _srcChannelLayout;
    AVSampleFormat _srcAudioFormat = AV_SAMPLE_FMT_NONE;
    int64_t _srcSampleRate;
    uint8_t *_audioBuffer = nullptr;
    uint8_t *_audioBuffer1 = nullptr;
    unsigned int _audioBufferLen = 0;
    unsigned int _audioBufferLen1 = 0;
    int _nbSamples = 0;
    int64_t audioOffset = 0;

    int sampleRate;
    int channels;
    AVSampleFormat format = AV_SAMPLE_FMT_NONE;
    uint32_t bufferFrameCount = 0;

    // video
    SwsContext *_swsCtx = nullptr;
    AVPixelFormat _srcVideoFormat = AV_PIX_FMT_NONE;
    int64_t width = 0;
    int64_t height = 0;
    uint8_t *_videoBuffer = nullptr;
    unsigned int _videoBufferLen = 0;
    uint8_t *videoData[4];
    int linesize[4];

    virtual uint32_t getCurrentPadding() = 0;
    virtual int writeBuffer(uint8_t *data, int64_t length) = 0;
    virtual void flushVideoBuffer() = 0;
    virtual void start() = 0;
    virtual void stop() = 0;
    virtual void close() = 0;
  };
}