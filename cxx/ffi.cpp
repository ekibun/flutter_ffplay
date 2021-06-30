#ifdef _MSC_VER
#define DLLEXPORT __declspec(dllexport)
#else
#define DLLEXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#include "string"
#include "list"

#include <mmdeviceapi.h>
#include <audiopolicy.h>

const CLSID CLSID_MMDeviceEnumerator = __uuidof(MMDeviceEnumerator);
const IID IID_IMMDeviceEnumerator = __uuidof(IMMDeviceEnumerator);
const IID IID_IAudioClient = __uuidof(IAudioClient);
const IID IID_IAudioRenderClient = __uuidof(IAudioRenderClient);

#define DEFINE_CLASS_GET_PROP(class, prop) \
  DLLEXPORT int64_t class##_get_##prop(class *p) { return (int64_t)p->prop; }

#define DEFINE_CLASS_METHOD(class, method) \
  DLLEXPORT int64_t class##_##method(class *p) { return (int64_t)p->method(); }

#define DEFINE_CLASS_METHOD_VOID(class, method) \
  DLLEXPORT int64_t class##_##method(class *p) { return p->method(), 0; }

extern "C"
{
#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libswresample/swresample.h"

  class AudioClient
  {
  public:
    SwrContext *_swrCtx = 0;
    int64_t _srcChannelLayout;
    int64_t _srcFormat;
    int64_t _srcSampleRate;
    uint8_t *_buffer = nullptr;
    uint8_t *_buffer1 = nullptr;
    unsigned int _bufferLen = 0;
    unsigned int _bufferLen1 = 0;
    int _nbSamples = 0;
    int64_t _offset = 0;

    int sampleRate;
    int channels;
    AVSampleFormat format = AV_SAMPLE_FMT_NONE;
    uint32_t bufferFrameCount;

    virtual uint32_t getCurrentPadding() = 0;
    virtual int writeBuffer(uint8_t *data, int64_t length) = 0;
    virtual void start() = 0;
    virtual void stop() = 0;
    virtual void close() = 0;
  };

  class AudioClientImpl : public AudioClient
  {
    IMMDeviceEnumerator *pEnumerator = nullptr;
    IMMDevice *pDevice = nullptr;
    IAudioClient *pAudioClient = nullptr;
    WAVEFORMATEX *pwfx = nullptr;
    IAudioRenderClient *pRenderClient = nullptr;

    static AVSampleFormat getSampleFormat(WAVEFORMATEX *wave_format)
    {
      switch (wave_format->wFormatTag)
      {
      case WAVE_FORMAT_PCM:
        if (16 == wave_format->wBitsPerSample)
        {
          return AV_SAMPLE_FMT_S16;
        }
        if (32 == wave_format->wBitsPerSample)
        {
          return AV_SAMPLE_FMT_S32;
        }
        break;
      case WAVE_FORMAT_IEEE_FLOAT:
        return AV_SAMPLE_FMT_FLT;
      case WAVE_FORMAT_ALAW:
      case WAVE_FORMAT_MULAW:
        return AV_SAMPLE_FMT_U8;
      case WAVE_FORMAT_EXTENSIBLE:
      {
        const WAVEFORMATEXTENSIBLE *wfe = reinterpret_cast<const WAVEFORMATEXTENSIBLE *>(wave_format);
        if (KSDATAFORMAT_SUBTYPE_IEEE_FLOAT == wfe->SubFormat)
        {
          return AV_SAMPLE_FMT_FLT;
        }
        if (KSDATAFORMAT_SUBTYPE_PCM == wfe->SubFormat)
        {
          if (16 == wave_format->wBitsPerSample)
          {
            return AV_SAMPLE_FMT_S16;
          }
          if (32 == wave_format->wBitsPerSample)
          {
            return AV_SAMPLE_FMT_S32;
          }
        }
        break;
      }
      default:
        break;
      }
      return AV_SAMPLE_FMT_NONE;
    }

  public:
    int64_t getSampleRate()
    {
      return pwfx->nSamplesPerSec;
    }
    virtual int64_t getChannels()
    {
      return pwfx->nChannels;
    }
    AVSampleFormat getFormat()
    {
      return format;
    }
    virtual int64_t getBufferFrameCount()
    {
      return bufferFrameCount;
    }

    virtual uint32_t getCurrentPadding()
    {
      uint32_t numFramesPadding = 0;
      if (pAudioClient)
        pAudioClient->GetCurrentPadding(&numFramesPadding);
      return numFramesPadding;
    }
    int writeBuffer(uint8_t *data, int64_t length)
    {
      if (!pRenderClient)
        return -1;
      int requestBuffer = min(bufferFrameCount - getCurrentPadding(), length);
      uint8_t *buffer;
      pRenderClient->GetBuffer(requestBuffer, &buffer);
      if (!buffer)
        return -1;
      int count = requestBuffer * av_get_bytes_per_sample(format) * channels;
      memcpy_s(buffer, count, data, count);
      if (pRenderClient->ReleaseBuffer(requestBuffer, 0) < 0)
        return -1;
      return requestBuffer;
    }
    void start()
    {
      if (!pAudioClient)
        return;
      pAudioClient->Start();
    }
    void stop()
    {
      if (!pAudioClient)
        return;
      pAudioClient->Stop();
    }
    void close()
    {
      if (pwfx)
        CoTaskMemFree(pwfx);
      pwfx = nullptr;
      if (pRenderClient)
        pRenderClient->Release();
      pRenderClient = nullptr;
      if (pAudioClient)
        pAudioClient->Release();
      pAudioClient = nullptr;
      if (pDevice)
        pDevice->Release();
      pDevice = nullptr;
      if (pEnumerator)
        pEnumerator->Release();
      pEnumerator = nullptr;
    }

    AudioClientImpl()
    {
      try
      {
        CoInitialize(NULL);
        CoCreateInstance(
            CLSID_MMDeviceEnumerator, NULL,
            CLSCTX_ALL, IID_IMMDeviceEnumerator,
            (void **)&pEnumerator);
        if (!pEnumerator)
          throw std::exception("Create IMMDeviceEnumerator failed");
        pEnumerator->GetDefaultAudioEndpoint(eRender, eConsole, &pDevice);
        if (!pDevice)
          throw std::exception("IMMDeviceEnumerator GetDefaultAudioEndpoint failed");
        pDevice->Activate(
            IID_IAudioClient, CLSCTX_ALL,
            NULL, (void **)&pAudioClient);
        if (!pAudioClient)
          throw std::exception("IMMDevice Activate failed");
        pAudioClient->GetMixFormat(&pwfx);
        if (!pwfx)
          throw std::exception("IAudioClient GetMixFormat failed");
        sampleRate = pwfx->nSamplesPerSec;
        channels = pwfx->nChannels;
        format = getSampleFormat(pwfx);
        if (pAudioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 10000000, 0, pwfx, NULL) < 0)
          throw std::exception("IAudioClient Initialize failed");
        pAudioClient->GetBufferSize(&bufferFrameCount);
        if (bufferFrameCount <= 0)
          throw std::exception("IAudioClient GetBufferSize failed");
        pAudioClient->GetService(
            IID_IAudioRenderClient,
            (void **)&pRenderClient);
        if (!pAudioClient)
          throw std::exception("IAudioClient GetService failed");
      }
      catch (std::exception &e)
      {
        close();
        throw e;
      }
    }
  };

  DLLEXPORT int64_t AudioClient_get_bufferDuration(AudioClient *audio)
  {
    return audio->bufferFrameCount * 1000 / audio->sampleRate;
  }

  DLLEXPORT int64_t AudioClient_flushBuffer(AudioClient *audio)
  {
    int offset = audio->writeBuffer(
        audio->_buffer1 + audio->_offset, audio->_nbSamples - audio->_offset);
    if (offset < 0)
      return 0;
    audio->_offset += offset;
    if (audio->_offset < audio->_nbSamples)
      return audio->_offset - audio->_nbSamples;
    return audio->getCurrentPadding() * AV_TIME_BASE / audio->sampleRate + 1;
  }

  DLLEXPORT AudioClient *AudioClient_create()
  {
    try
    {
      return new AudioClientImpl();
    }
    catch (std::exception &)
    {
      return nullptr;
    }
  }

  DEFINE_CLASS_METHOD_VOID(AudioClient, start)
  DEFINE_CLASS_METHOD_VOID(AudioClient, stop)
  DEFINE_CLASS_METHOD_VOID(AudioClient, close)

  DEFINE_CLASS_GET_PROP(AVPacket, stream_index)

  DLLEXPORT void AVPacket_close(AVPacket *packet)
  {
    av_packet_free(&packet);
  }

  DLLEXPORT void AVFrame_close(AVFrame *frame)
  {
    av_frame_free(&frame);
  }

  DLLEXPORT int64_t AudioClient_postFrame(AudioClient *audio, AVFrame *frame)
  {
    if (!audio->_swrCtx || audio->_srcChannelLayout != frame->channel_layout || audio->_srcFormat != frame->format || audio->_srcSampleRate != frame->sample_rate)
    {
      if (audio->_swrCtx)
        swr_free(&audio->_swrCtx);
      audio->_swrCtx = swr_alloc_set_opts(
          nullptr,
          av_get_default_channel_layout(audio->channels),
          audio->format,
          audio->sampleRate,
          frame->channel_layout,
          (AVSampleFormat)frame->format,
          frame->sample_rate, 0, nullptr);
      if (!audio->_swrCtx || swr_init(audio->_swrCtx) < 0)
        return -1;
      audio->_srcChannelLayout = frame->channel_layout;
      audio->_srcFormat = frame->format;
      audio->_srcSampleRate = frame->sample_rate;
    }
    int inCount = frame->nb_samples;
    int outCount = inCount * audio->sampleRate / frame->sample_rate + 256;
    int outSize = av_samples_get_buffer_size(nullptr, audio->channels, outCount, audio->format, 0);
    if (outSize < 0)
      return -2;
    av_fast_malloc(&audio->_buffer, &audio->_bufferLen, outSize);
    if (!audio->_buffer)
      return -3;
    audio->_nbSamples =
        swr_convert(audio->_swrCtx, &audio->_buffer, outCount, (const uint8_t **)frame->extended_data, inCount);
    uint8_t *buffer = audio->_buffer;
    unsigned int bufferLen = audio->_bufferLen;
    audio->_buffer = audio->_buffer1;
    audio->_bufferLen = audio->_bufferLen1;
    audio->_buffer1 = buffer;
    audio->_bufferLen1 = bufferLen;
    audio->_offset = 0;
    return 0;
  }

  DLLEXPORT int64_t AVStream_get_codecType(AVStream *stream)
  {
    return stream->codecpar->codec_type;
  }

  DLLEXPORT int64_t AVStream_getFramePts(AVStream *stream, AVFrame *frame)
  {
    return frame->best_effort_timestamp * av_q2d(stream->time_base) * AV_TIME_BASE;
  }

  DLLEXPORT AVCodecContext *AVStream_createCodec(AVStream *stream)
  {
    auto pCodec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!pCodec)
      return nullptr;
    AVCodecContext *ctx = avcodec_alloc_context3(pCodec);
    ctx->opaque = nullptr;
    int ret = avcodec_parameters_to_context(ctx, stream->codecpar);
    if (ret == 0)
    {
      ret = avcodec_open2(ctx, pCodec, nullptr);
      if (ret == 0)
        return ctx;
    }
    if (ctx)
      avcodec_free_context(&ctx);
    return nullptr;
  }

  DLLEXPORT void AVCodecContext_flush(AVCodecContext *ctx)
  {
    avcodec_flush_buffers(ctx);
  }

  DLLEXPORT void AVCodecContext_close(AVCodecContext *ctx)
  {
    if (ctx->opaque)
      av_frame_free((AVFrame **)&(ctx->opaque));
    avcodec_free_context(&ctx);
  }

  DLLEXPORT AVFrame *AVCodecContext_sendPacketAndGetFrame(AVCodecContext *ctx, AVPacket *p)
  {
    AVFrame *frame = (AVFrame *)ctx->opaque;
    if (!frame)
      ctx->opaque = frame = av_frame_alloc();
    if (avcodec_send_packet(ctx, p) == 0 &&
        avcodec_receive_frame(ctx, frame) == 0)
    {
      ctx->opaque = nullptr;
      return frame;
    }
    return nullptr;
  }

  DLLEXPORT AVFormatContext *AVFormatContext_create(
      void *opaque, int64_t bufferSize,
      int (*read_packet)(void *opaque, uint8_t *buf, int buf_size),
      int64_t (*seek)(void *opaque, int64_t offset, int whence))
  {
    AVFormatContext *ctx;
    uint8_t *buffer = (uint8_t *)av_malloc(bufferSize);
    AVIOContext *ioCtx = avio_alloc_context(
        buffer, bufferSize, 0, opaque, read_packet, nullptr, seek);
    ctx = avformat_alloc_context();
    ctx->pb = ioCtx;
    int ret = avformat_open_input(&ctx, nullptr, nullptr, nullptr);
    if (ret == 0)
      return ctx;
    if (ctx)
      avformat_close_input(&ctx);
    return nullptr;
  }

  DLLEXPORT void AVFormatContext_close(AVFormatContext *ctx)
  {
    avformat_close_input(&ctx);
  }

  DEFINE_CLASS_GET_PROP(AVFormatContext, duration)
  DEFINE_CLASS_GET_PROP(AVFormatContext, streams)

  DLLEXPORT int64_t AVFormatContext_seekTo(
      AVFormatContext *ctx,
      int64_t stream_index,
      int64_t min_ts,
      int64_t ts,
      int64_t max_ts,
      int64_t flags)
  {
    return avformat_seek_file(ctx, stream_index, min_ts, ts, max_ts, flags);
  }

  DLLEXPORT int64_t AVFormatContext_getPacket(AVFormatContext *ctx, AVPacket **packet)
  {
    *packet = *packet ? *packet : av_packet_alloc();
    int ret = av_read_frame(ctx, *packet);
    if (ret)
      av_packet_free(packet);
    return ret;
  }

  DLLEXPORT int64_t AVFormatContext_findStreamCount(AVFormatContext *ctx)
  {
    if (avformat_find_stream_info(ctx, nullptr) != 0)
      return -1;
    return ctx->nb_streams;
  }
}