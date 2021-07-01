#ifdef _MSC_VER
#include "../windows/audio.hpp"
#endif

class PlaybackClientImpl : public AudioClientImpl
{
  void flushVideoBuffer() {}
};

extern "C"
{
  DLLEXPORT PlaybackClient *Mock_createPlayback()
  {
    try
    {
      return new PlaybackClientImpl();
    }
    catch (std::exception &)
    {
      return nullptr;
    }
  }
}