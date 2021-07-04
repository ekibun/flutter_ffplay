#include <jni.h>
extern "C"
{
#include "libavcodec/jni.h"

  JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *res)
  {
    av_jni_set_java_vm(vm, 0);
    return JNI_VERSION_1_4;
  }

  JNIEXPORT jbyteArray JNICALL
  Java_soko_ekibun_ffmpeg_PlaybackImpl_getByteBuffer(
      JNIEnv *env,
      jobject thiz,
      jlong buffer,
      jint size)
  {
    jbyteArray arr = env->NewByteArray(size);
    env->SetByteArrayRegion(arr, 0, size, (int8_t *)buffer);
    return arr;
  }
}
