#define DEFINE_CLASS_GET_PROP(class, prop) \
  DLLEXPORT int64_t class##_get_##prop(class *p) { return (int64_t)p->prop; }

#define DEFINE_CLASS_METHOD(class, method) \
  DLLEXPORT int64_t class##_##method(class *p) { return (int64_t)p->method(); }

#define DEFINE_CLASS_METHOD_VOID(class, method) \
  DLLEXPORT int64_t class##_##method(class *p) { return p->method(), 0; }

#include "ffi.h"

extern "C"
{

  DLLEXPORT int64_t PlaybackClient_get_audioBufferDuration(PlaybackClient *audio)
  {
    return audio->bufferFrameCount * 1000 / audio->sampleRate;
  }

  DLLEXPORT int64_t PlaybackClient_flushAudioBuffer(PlaybackClient *audio)
  {
    if (audio->audioOffset < audio->_nbSamples)
    {
      int offset = audio->writeBuffer(
          audio->_audioBuffer1 + audio->audioOffset, audio->_nbSamples - audio->audioOffset);
      if (offset < 0)
        return 0;
      audio->audioOffset += offset;
      if (audio->audioOffset < audio->_nbSamples)
        return audio->audioOffset - audio->_nbSamples;
    }
    return audio->getCurrentPadding() * AV_TIME_BASE / audio->sampleRate + 1;
  }

  DEFINE_CLASS_METHOD_VOID(PlaybackClient, flushVideoBuffer)
  DEFINE_CLASS_METHOD_VOID(PlaybackClient, start)
  DEFINE_CLASS_METHOD_VOID(PlaybackClient, stop)
  DEFINE_CLASS_METHOD_VOID(PlaybackClient, close)

  DEFINE_CLASS_GET_PROP(AVPacket, stream_index)

  DLLEXPORT void AVPacket_close(AVPacket *packet)
  {
    av_packet_free(&packet);
  }

  DLLEXPORT void AVFrame_close(AVFrame *frame)
  {
    av_frame_free(&frame);
  }

  int64_t AudioClient_postFrame(PlaybackClient *audio, AVFrame *frame)
  {
    if (!audio->_swrCtx || audio->_srcChannelLayout != frame->channel_layout || audio->_srcAudioFormat != frame->format || audio->_srcSampleRate != frame->sample_rate)
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
      audio->_srcAudioFormat = (AVSampleFormat)frame->format;
      audio->_srcSampleRate = frame->sample_rate;
    }
    int inCount = frame->nb_samples;
    int outCount = inCount * audio->sampleRate / frame->sample_rate + 256;
    int outSize = av_samples_get_buffer_size(nullptr, audio->channels, outCount, audio->format, 0);
    if (outSize < 0)
      return -2;
    av_fast_malloc(&audio->_audioBuffer, &audio->_audioBufferLen, outSize);
    if (!audio->_audioBuffer)
      return -3;
    audio->_nbSamples =
        swr_convert(audio->_swrCtx, &audio->_audioBuffer, outCount, (const uint8_t **)frame->extended_data, inCount);
    uint8_t *buffer = audio->_audioBuffer;
    unsigned int bufferLen = audio->_audioBufferLen;
    audio->_audioBuffer = audio->_audioBuffer1;
    audio->_audioBufferLen = audio->_audioBufferLen1;
    audio->_audioBuffer1 = buffer;
    audio->_audioBufferLen1 = bufferLen;
    audio->audioOffset = 0;
    return 0;
  }

  DLLEXPORT int64_t PlaybackClient_postFrame(int64_t type, PlaybackClient *playback, AVFrame *frame)
  {
    if (type == AVMEDIA_TYPE_AUDIO)
      return AudioClient_postFrame(playback, frame);
    if (!playback->_swsCtx || playback->width != frame->width || playback->height != frame->height || playback->_srcVideoFormat != frame->format)
    {
      if (playback->_swsCtx)
        sws_freeContext(playback->_swsCtx);
      playback->_swsCtx = nullptr;
      int bufSize = av_image_get_buffer_size(AV_PIX_FMT_RGBA, frame->width, frame->height, 1);
      playback->width = frame->width;
      playback->height = frame->height;
      av_fast_malloc(&playback->_videoBuffer, &playback->_videoBufferLen, bufSize);
      if (!playback->_videoBuffer)
        return -1;
      av_image_fill_arrays(
          playback->videoData,
          playback->linesize,
          playback->_videoBuffer,
          AV_PIX_FMT_RGBA,
          playback->width,
          playback->height, 1);
      playback->_swsCtx = sws_getContext(
          frame->width,
          frame->height,
          (AVPixelFormat)frame->format,
          playback->width,
          playback->height,
          AV_PIX_FMT_RGBA,
          SWS_POINT,
          nullptr, nullptr, nullptr);
    }
    if (!playback->_swsCtx)
      return -1;
    sws_scale(
        playback->_swsCtx,
        frame->data,
        frame->linesize,
        0,
        frame->height,
        playback->videoData,
        playback->linesize);
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