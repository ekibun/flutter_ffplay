#define DEFINE_CLASS_GET_PROP(class, prop) \
  DLLEXPORT int64_t class##_get_##prop(class *p) { return (int64_t)p->prop; }

#define DEFINE_CLASS_METHOD(class, method) \
  DLLEXPORT int64_t class##_##method(class *p) { return (int64_t)p->method(); }

#define DEFINE_CLASS_METHOD_VOID(class, method) \
  DLLEXPORT int64_t class##_##method(class *p) { return p->method(), 0; }

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

  struct SWContext
  {
    // audio
    int64_t sampleRate;
    int64_t channels;
    int64_t audioFormat = AV_SAMPLE_FMT_NONE;
    uint8_t *audioBuffer = nullptr;
    int64_t audioBufferSize = 0;
    // video
    int64_t width = 0;
    int64_t height = 0;
    int64_t videoFormat = AV_SAMPLE_FMT_NONE;
    uint8_t *videoBuffer = nullptr;
    int64_t videoBufferSize = 0;
    // opaque
    SwrContext *_swrCtx = nullptr;
    int64_t _srcChannelLayout = 0;
    AVSampleFormat _srcAudioFormat = AV_SAMPLE_FMT_NONE;
    int64_t _srcSampleRate = 0;
    uint8_t *_audioBuffer1 = nullptr;
    unsigned int _audioBufferLen = 0;
    unsigned int _audioBufferLen1 = 0;
    SwsContext *_swsCtx = nullptr;
    AVPixelFormat _srcVideoFormat = AV_PIX_FMT_NONE;
    unsigned int _videoBufferLen = 0;
    uint8_t *_videoData[4];
    int _linesize[4];
  };

  DLLEXPORT int64_t sizeOfSWContext()
  {
    return sizeof(SWContext);
  }

  DEFINE_CLASS_GET_PROP(AVPacket, stream_index)

  DLLEXPORT void AVPacket_close(AVPacket *packet)
  {
    av_packet_free(&packet);
  }

  DLLEXPORT void AVFrame_close(AVFrame *frame)
  {
    av_frame_free(&frame);
  }

  int64_t SWContext_postFrameAudio(SWContext *ctx, AVFrame *frame)
  {
    if (ctx->audioFormat == AV_SAMPLE_FMT_NONE)
      return -1;
    if (!ctx->_swrCtx ||
        ctx->_srcChannelLayout != frame->channel_layout ||
        ctx->_srcAudioFormat != frame->format ||
        ctx->_srcSampleRate != frame->sample_rate)
    {
      if (ctx->_swrCtx)
        swr_free(&ctx->_swrCtx);
      ctx->_swrCtx = swr_alloc_set_opts(
          nullptr,
          av_get_default_channel_layout(ctx->channels),
          (AVSampleFormat)ctx->audioFormat,
          ctx->sampleRate,
          frame->channel_layout,
          (AVSampleFormat)frame->format,
          frame->sample_rate, 0, nullptr);
      if (!ctx->_swrCtx || swr_init(ctx->_swrCtx) < 0)
        return -1;
      ctx->_srcChannelLayout = frame->channel_layout;
      ctx->_srcAudioFormat = (AVSampleFormat)frame->format;
      ctx->_srcSampleRate = frame->sample_rate;
    }
    int inCount = frame->nb_samples;
    int outCount = inCount * ctx->sampleRate / frame->sample_rate + 256;
    int outSize = av_samples_get_buffer_size(
        nullptr, ctx->channels, outCount, (AVSampleFormat)ctx->audioFormat, 0);
    if (outSize < 0)
      return -2;
    av_fast_malloc(&ctx->_audioBuffer1, &ctx->_audioBufferLen, outSize);
    if (!ctx->_audioBuffer1)
      return -3;
    int frameCount =
        swr_convert(ctx->_swrCtx, &ctx->_audioBuffer1, outCount, (const uint8_t **)frame->extended_data, inCount);
    ctx->audioBufferSize = av_samples_get_buffer_size(
        nullptr, ctx->channels, frameCount, (AVSampleFormat)ctx->audioFormat, 0);
    uint8_t *buffer = ctx->_audioBuffer1;
    unsigned int bufferLen = ctx->_audioBufferLen1;
    ctx->_audioBuffer1 = ctx->audioBuffer;
    ctx->_audioBufferLen1 = ctx->_audioBufferLen;
    ctx->audioBuffer = buffer;
    ctx->_audioBufferLen = bufferLen;
    return 0;
  }

  DLLEXPORT int64_t SWContext_postFrameVideo(SWContext *ctx, AVFrame *frame)
  {
    if (!ctx->_swsCtx ||
        ctx->width != frame->width ||
        ctx->height != frame->height ||
        ctx->_srcVideoFormat != frame->format)
    {
      if (ctx->_swsCtx)
        sws_freeContext(ctx->_swsCtx);
      ctx->_swsCtx = nullptr;
      ctx->videoBufferSize = av_image_get_buffer_size((AVPixelFormat)ctx->videoFormat, frame->width, frame->height, 1);
      if (!ctx->videoBufferSize)
        return -1;
      ctx->width = frame->width;
      ctx->height = frame->height;
      av_fast_malloc(&ctx->videoBuffer, &ctx->_videoBufferLen, ctx->videoBufferSize);
      if (!ctx->videoBuffer)
        return -1;
      av_image_fill_arrays(
          ctx->_videoData,
          ctx->_linesize,
          ctx->videoBuffer,
          (AVPixelFormat)ctx->videoFormat,
          ctx->width,
          ctx->height, 1);
      ctx->_swsCtx = sws_getContext(
          frame->width,
          frame->height,
          (AVPixelFormat)frame->format,
          ctx->width,
          ctx->height,
          AV_PIX_FMT_RGBA,
          SWS_POINT,
          nullptr, nullptr, nullptr);
    }
    if (!ctx->_swsCtx)
      return -1;
    sws_scale(
        ctx->_swsCtx,
        frame->data,
        frame->linesize,
        0,
        frame->height,
        ctx->_videoData,
        ctx->_linesize);
    return 0;
  }
  DLLEXPORT int64_t SWContext_postFrame(int64_t type, SWContext *ctx, AVFrame *frame)
  {
    switch (type)
    {
    case AVMEDIA_TYPE_AUDIO:
      return SWContext_postFrameAudio(ctx, frame);
    case AVMEDIA_TYPE_VIDEO:
      return SWContext_postFrameVideo(ctx, frame);
    default:
      return -1;
    }
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

  DLLEXPORT AVIOContext *AVIOContext_create(
      void *opaque, int64_t bufferSize,
      int (*read_packet)(void *opaque, uint8_t *buf, int buf_size),
      int64_t (*seek)(void *opaque, int64_t offset, int whence))
  {
    return avio_alloc_context(
        (uint8_t *)av_malloc(bufferSize), bufferSize, 0, opaque, read_packet, nullptr, seek);
  }

  DLLEXPORT AVFormatContext *AVFormatContext_create(
      int (*io_open)(AVFormatContext *s, AVIOContext **pb, const char *url, int flags, AVDictionary **options),
      void (*io_close)(AVFormatContext *s, AVIOContext *pb))
  {
    AVFormatContext *ctx = avformat_alloc_context();
    ctx->io_open = io_open;
    ctx->io_close = io_close;
    ctx->flags |= AVFMT_FLAG_CUSTOM_IO;
    return ctx;
  }

  DLLEXPORT int64_t AVFormatContext_open(AVFormatContext *ctx, char *url)
  {
    return avformat_open_input(&ctx, url, nullptr, nullptr);
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