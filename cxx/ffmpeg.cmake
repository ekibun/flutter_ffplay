cmake_minimum_required(VERSION 3.7 FATAL_ERROR)

if (ANDROID)
  set(FFMPEG_PATH "${CMAKE_CURRENT_LIST_DIR}/build/android_${CMAKE_ANDROID_ARCH}")
  set(ffmpeg-lib
    z
  )
endif ()

if (WIN32)
  set(FFMPEG_PATH "${CMAKE_CURRENT_LIST_DIR}/build/win32_x86_64")
  
  set(ffmpeg-lib
    bcrypt
  )
endif ()

set(ffmpeg-lib
  "${FFMPEG_PATH}/lib/libavformat.a"
  "${FFMPEG_PATH}/lib/libavcodec.a"
  "${FFMPEG_PATH}/lib/libavutil.a"
  "${FFMPEG_PATH}/lib/libswresample.a"
  "${FFMPEG_PATH}/lib/libswscale.a"
  ${ffmpeg-lib}
)