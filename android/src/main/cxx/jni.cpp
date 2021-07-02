#include <jni.h>
#include "../../../../cxx/ffi.h"
#include "android/log.h"

JNIEnv *getEnv(JavaVM *gJvm)
{
  JNIEnv *env;
  int status = gJvm->GetEnv((void **)&env, JNI_VERSION_1_6);
  if (status < 0)
  {
    status = gJvm->AttachCurrentThread(&env, NULL);
    if (status < 0)
    {
      return nullptr;
    }
  }
  return env;
}

class Playback : public PlaybackClient
{
  JavaVM *vm;

public:
  jobject playback;

  Playback(JNIEnv *env, jobject instance)
  {
    format = AV_SAMPLE_FMT_S16;
    sampleRate = 44100;
    channels = 2;
    env->GetJavaVM(&vm);
    playback = env->NewGlobalRef(instance);
    jclass clazz = env->GetObjectClass(playback);
  }
  uint32_t getCurrentPadding()
  {
    auto env = getEnv(vm);
    jclass clazz = env->GetObjectClass(playback);
    jmethodID method = env->GetMethodID(clazz, "getCurrentPadding", "()I");
    return env->CallIntMethod(playback, method);
  }
  int writeBuffer(uint8_t *data, int64_t length)
  {
    auto env = getEnv(vm);
    jclass clazz = env->GetObjectClass(playback);
    jmethodID method = env->GetMethodID(clazz, "writeBuffer", "([BI)I");
    jbyteArray audio_sample_array = env->NewByteArray(length);
    env->SetByteArrayRegion(audio_sample_array, 0, length, (const jbyte *)data);
    int ret = env->CallIntMethod(playback, method);
    env->DeleteLocalRef(audio_sample_array);
    return ret;
  }
  void flushVideoBuffer()
  {
    auto env = getEnv(vm);
    jclass clazz = env->GetObjectClass(playback);
    jmethodID method = env->GetMethodID(clazz, "flushVideoBuffer", "()V");
    env->CallVoidMethod(playback, method);
  }
  void start()
  {
    auto env = getEnv(vm);
    jclass clazz = env->GetObjectClass(playback);
    jmethodID method = env->GetMethodID(clazz, "start", "()V");
    env->CallVoidMethod(playback, method);
  }
  void stop()
  {
    auto env = getEnv(vm);
    jclass clazz = env->GetObjectClass(playback);
    jmethodID method = env->GetMethodID(clazz, "stop", "()V");
    env->CallVoidMethod(playback, method);
  }
  void close()
  {
    auto env = getEnv(vm);
    jclass clazz = env->GetObjectClass(playback);
    jmethodID method = env->GetMethodID(clazz, "close", "()V");
    env->CallVoidMethod(playback, method);
    env->DeleteGlobalRef(playback);
    delete this;
  };
};

extern "C"
{
  JNIEXPORT jlong JNICALL
  Java_soko_ekibun_ffmpeg_PlaybackImpl_bindNative(
      JNIEnv *env, jobject instance)
  {
    try
    {
      return (jlong) new Playback(env, instance);
    }
    catch (...)
    {
      return 0;
    }
  }

  JNIEXPORT jobject JNICALL
  Java_soko_ekibun_ffmpeg_PlaybackImpl_fromNative(
      JNIEnv *env, jlong ptr)
  {
    return env->NewLocalRef(((Playback *)ptr)->playback);
  }
}
