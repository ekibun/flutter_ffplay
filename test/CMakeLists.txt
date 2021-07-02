cmake_minimum_required(VERSION 3.15)
add_compile_options("$<$<CXX_COMPILER_ID:MSVC>:/utf-8>")

set(PLUGIN_NAME "ffmpeg_plugin")

project(${PLUGIN_NAME} LANGUAGES CXX)

if (CMAKE_SYSTEM_NAME MATCHES "Linux")
  target_compile_options(${PLUGIN_NAME} PRIVATE "-fPIC")
endif ()

add_library(${PLUGIN_NAME} SHARED
"${CMAKE_CURRENT_SOURCE_DIR}/mock.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/../cxx/ffi.cpp"
)

include("${CMAKE_CURRENT_SOURCE_DIR}/../cxx/ffmpeg.cmake")