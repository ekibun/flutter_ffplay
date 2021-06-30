#include "../cxx/windows.hpp"

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