#include "exception"

#include <mmdeviceapi.h>
#include <audiopolicy.h>

extern "C"
{
#include "libswresample/swresample.h"
}

const CLSID CLSID_MMDeviceEnumerator = __uuidof(MMDeviceEnumerator);
const IID IID_IMMDeviceEnumerator = __uuidof(IMMDeviceEnumerator);
const IID IID_IAudioClient = __uuidof(IAudioClient);
const IID IID_IAudioRenderClient = __uuidof(IAudioRenderClient);

class AudioClientImpl
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
  uint32_t audioBufferFrameSize;
  int64_t channels;
  AVSampleFormat audioFormat;
  int64_t sampleRate;

  int getCurrentPadding()
  {
    uint32_t numFramesPadding = 0;
    if (pAudioClient)
      pAudioClient->GetCurrentPadding(&numFramesPadding);
    return numFramesPadding;
  }
  int64_t flushAudioBuffer(uint8_t *data, int64_t length)
  {
    if (length <= 0)
      return getCurrentPadding();
    int bytesPerFrame = av_get_bytes_per_sample(audioFormat) * channels;
    if (bytesPerFrame == 0)
      return -1;
    length /= bytesPerFrame;
    if (!pRenderClient)
      return -1;
    int requestBuffer = min(audioBufferFrameSize - getCurrentPadding(), length);
    if (requestBuffer == 0)
      return 0;
    uint8_t *buffer;
    pRenderClient->GetBuffer(requestBuffer, &buffer);
    if (!buffer)
      return -1;
    int count = requestBuffer * bytesPerFrame;
    memcpy_s(buffer, count, data, count);
    if (pRenderClient->ReleaseBuffer(requestBuffer, 0) < 0)
      return -1;
    return count;
  }
  int resume()
  {
    if (!pAudioClient)
      return -1;
    pAudioClient->Start();
    return 0;
  }
  int stop()
  {
    if (!pAudioClient)
      return -1;
    pAudioClient->Stop();
    return 0;
  }
  int pause()
  {
    return stop();
  }
  void _close()
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
  ~AudioClientImpl()
  {
    _close();
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
      audioFormat = getSampleFormat(pwfx);
      if (pAudioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 10000000, 0, pwfx, NULL) < 0)
        throw std::exception("IAudioClient Initialize failed");
      pAudioClient->GetBufferSize(&audioBufferFrameSize);
      if (audioBufferFrameSize <= 0)
        throw std::exception("IAudioClient GetBufferSize failed");
      pAudioClient->GetService(
          IID_IAudioRenderClient,
          (void **)&pRenderClient);
      if (!pAudioClient)
        throw std::exception("IAudioClient GetService failed");
    }
    catch (std::exception &e)
    {
      _close();
      throw e;
    }
  }
};
