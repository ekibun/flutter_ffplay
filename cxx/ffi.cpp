#ifdef _MSC_VER
#define DLLEXPORT __declspec(dllexport)
#else
#define DLLEXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#include "string"
#include "list"

extern "C"
{
#include "libavformat/avformat.h"

  class FFMpegFormatContext
  {
  public:
    AVFormatContext *_ctx;
    AVIOContext *_ioCtx;

    void _close()
    {
      if (_ctx)
        avformat_close_input(&_ctx);
      if (_ioCtx)
        av_free(_ioCtx);
    }

    FFMpegFormatContext(
        void *opaque, int64_t bufferSize,
        int (*read_packet)(void *opaque, uint8_t *buf, int buf_size),
        int64_t (*seek)(void *opaque, int64_t offset, int whence))
    {
      uint8_t *_buffer = (uint8_t *)av_malloc(bufferSize);
      AVIOContext *_ioCtx = avio_alloc_context(
          _buffer, bufferSize, 0, opaque, read_packet, nullptr, seek);
      _ctx = avformat_alloc_context();
      _ctx->pb = _ioCtx;
      int ret = avformat_open_input(&_ctx, nullptr, nullptr, nullptr);
      if (ret != 0)
      {
        _close();
        throw std::exception("avformat_open_input failed");
      }
    }

    ~FFMpegFormatContext()
    {
      _close();
    }
  };
}

extern "C"
{
  DLLEXPORT FFMpegFormatContext *FFMpegFormatContext_create(
      void *opaque, int64_t bufferSize,
      int (*read_packet)(void *opaque, uint8_t *buf, int buf_size),
      int64_t (*seek)(void *opaque, int64_t offset, int whence))
  {
    try
    {
      return new FFMpegFormatContext(opaque, bufferSize, read_packet, seek);
    }
    catch (...)
    {
      return nullptr;
    }
  }

  DLLEXPORT void FFMpegFormatContext_close(
      FFMpegFormatContext *ctx)
  {
    delete ctx;
  }

  DLLEXPORT int64_t FFMpegFormatContext_getDuration(FFMpegFormatContext *ctx)
  {
    return ctx->_ctx->duration;
  }

  DLLEXPORT int64_t FFMpegFormatContext_seekTo(
      FFMpegFormatContext *ctx,
      int64_t stream_index,
      int64_t min_ts,
      int64_t ts,
      int64_t max_ts,
      int64_t flags)
  {
    return avformat_seek_file(ctx->_ctx, stream_index, min_ts, ts, max_ts, flags);
  }

  DLLEXPORT AVPacket *FFMpegFormatContext_getPacket(
      FFMpegFormatContext *ctx)
  {
    AVPacket *_packet = av_packet_alloc();
    if (av_read_frame(ctx->_ctx, _packet) == 0)
      return _packet;
    av_packet_free(&_packet);
    return nullptr;
  }

  DLLEXPORT int64_t FFMpegFormatContext_findStreamsCount(FFMpegFormatContext *ctx)
  {
    if (avformat_find_stream_info(ctx->_ctx, nullptr) != 0)
      return -1;
    return ctx->_ctx->nb_streams;
  }

  DLLEXPORT AVStream **FFMpegFormatContext_getStreams(FFMpegFormatContext *ctx)
  {
    return ctx->_ctx->streams;
  }
}