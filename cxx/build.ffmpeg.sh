#!/bin/bash
set -e

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

abi="$1_$2"

makedir=$DIR/build/.make/$abi
builddir=$DIR/build/$abi

CONFIG_ARGS=(
  --enable-pic
  --enable-static
  --disable-shared
  --disable-programs
  --disable-encoders
  --disable-muxers
  --disable-network
  --disable-postproc
  --disable-avdevice
  --disable-protocols
  --disable-doc
  --disable-filters
  --disable-avfilter
  --enable-cross-compile
  --prefix=$builddir/
)

exitUnsupport() {
  echo "unsupport abi $abi"
  exit 1
}

case $1 in
"win32")
  if [ $OSTYPE == msys ]; then
    if [ $CUDA_PATH ]; then
      CUDA_PATH="${CUDA_PATH//\\//}"
      export PATH=$CUDA_PATH:$PATH
      CONFIG_ARGS+=(
        --enable-nonfree
        --enable-cuda-nvcc
        --extra-cflags="-I$CUDA_PATH/include -I../../../mv-codec-headers/include"
        --extra-ldflags="-libpath:$CUDA_PATH/lib/x64"
      )
    fi
    CONFIG_ARGS+=(
      --toolchain=msvc
      --disable-cross-compile
      --arch=$2
      --target-os=win32
    )
  else
    case $2 in
    "x86")
      CROSS_PREFIX=i686-w64-mingw32
      ;;
    "x86_64")
      CROSS_PREFIX=x86_64-w64-mingw32
      ;;
    *)
      exitUnsupport
    esac
    CONFIG_ARGS+=(
      --arch=$2
      --target-os=mingw32
      --cross-prefix=$CROSS_PREFIX-
    )
  fi
  ;;
"android")
  case "$OSTYPE" in
  darwin*)
    HOST_OS="darwin"
    ;;
  msys*)
    HOST_OS="windows"
    ;;
  *)
    HOST_OS="linux"
    ;;
  esac
  TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_OS-x86_64"
  case $2 in
  "arm")
    MIN_API=16
    CC_PREFIX="$TOOLCHAIN/bin/armv7a-linux-androideabi$MIN_API"
    HOST=arm-linux-androideabi
    ;;
  "arm64")
    MIN_API=21
    CC_PREFIX="$TOOLCHAIN/bin/aarch64-linux-android$MIN_API"
    HOST=aarch64-linux-android
    ;;
  "x86")
    MIN_API=16
    CC_PREFIX="$TOOLCHAIN/bin/i686-linux-android$MIN_API"
    HOST=i686-linux-android
    CONFIG_ARGS+=(--disable-asm) # TODO https://trac.ffmpeg.org/ticket/7796
    ;;
  "x86_64")
    MIN_API=21
    CC_PREFIX="$TOOLCHAIN/bin/x86_64-linux-android$MIN_API"
    HOST=x86_64-linux-android
    CONFIG_ARGS+=(--disable-asm) # TODO https://stackoverflow.com/a/57707863
    ;;
  *)
    exitUnsupport
  esac
  ARCH_ROOT="$ANDROID_NDK_HOME/platforms/android-$MIN_API/arch-$2"
  CONFIG_ARGS+=(
    --arch=$2
    --target-os=$1
    --cc=$CC_PREFIX-clang
    --cxx=$CC_PREFIX-clang++
    --cross-prefix=$TOOLCHAIN/bin/$HOST-
    --extra-ldflags="-Wl,-rpath-link=$ARCH_ROOT/usr/lib"
  )
  ;;
*)
  exitUnsupport
esac

echo "build ffmpeg for $abi"

echo CONFIG_ARGS="${CONFIG_ARGS[@]}"

if [ -d $makedir ]; then
  rm -r $makedir
fi
mkdir -p $makedir

cd $makedir

$DIR/ffmpeg/configure "${CONFIG_ARGS[@]}"

if [ $1 == "android" ]; then
  sed -i.bak "s/#define HAVE_INET_ATON 0/#define HAVE_INET_ATON 1/" config.h
  sed -i.bak "s/#define getenv(x) NULL/\\/\\/ #define getenv(x) NULL/" config.h
fi

make -j8
make install

if [ $1 == "win32" ] && [ $OSTYPE != msys ]; then
  cp /usr/$CROSS_PREFIX/lib/libmingw32.a $builddir/lib/.
  cp /usr/$CROSS_PREFIX/lib/libmingwex.a $builddir/lib/.
  cp /usr/lib/gcc/$CROSS_PREFIX/$(ls /usr/lib/gcc/$CROSS_PREFIX/ | grep win32)/libgcc.a $builddir/lib/libgcc.a
fi
