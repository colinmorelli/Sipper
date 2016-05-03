#!/bin/bash

# SDK to build iOS against. This SDK must be installed.
export IOS_SDK_VERSION='9.3'

# Minimum iOS version to target
export MIN_IOS_VERSION='8.0'

# The version of OPUS to checkout. Can be either "master" or a valid tag
export OPUS_VERSION='1.1.2'

# The version of PJSIP to checkout. Can be either "trunk" or a valid tag
export PJSIP_VERSION='trunk'

# Base directory to write
export BASE_DIR=`pwd -P`

# Directory that stores configuration for each project
export CONFIG_DIR="${BASE_DIR}/configuration"

# Directory to store local repository copies
export SOURCE_DIR="${BASE_DIR}/vendor"

# Directory to output built artifacts to
export BUILD_DIR="${BASE_DIR}/out"

##-----------------------------------------------------------------------------
## Don't change below this line
##-----------------------------------------------------------------------------
export PRE='----->'
export DEVELOPER=$(xcode-select -print-path)

##-----------------------------------------------------------------------------
## Setup
##-----------------------------------------------------------------------------
CCACHE=`which ccache`
echo "Building with ccache... ${CCACHE:-no}"
echo "Building with debug... ${DEBUG:-no}"

if [ -z "${DEBUG}" ]; then
  OPT_CFLAGS="-Ofast -flto -g"
  OPT_LDFLAGS="-flto"
  OPT_CONFIG_ARGS=""
else
  OPT_CFLAGS="-O0 -fno-inline -g"
  OPT_LDFLAGS=""
  OPT_CONFIG_ARGS="--enable-assertions --disable-asm"
fi

set -e

##-----------------------------------------------------------------------------
## OPUS
##-----------------------------------------------------------------------------

function _exports_opus() {
  if [ "$1" == "i386" ] || [ "$1" == "x86_64" ]; then
    export PLATFORM="iPhoneSimulator"
    export EXTRA_CFLAGS="-arch $1"
    export EXTRA_CONFIG="--host=$1-apple-darwin_ios"
  else
    export PLATFORM="iPhoneOS"
    export EXTRA_CFLAGS="-arch $1"
    export EXTRA_CONFIG="--host=arm-apple-darwin"
  fi
}

function clean_opus() {
  echo "$PRE Cleaning OPUS"
  rm -rf $SOURCE_DIR/opus
  rm -rf $BUILD_DIR/opus
  echo "$PRE Successfully cleaned OPUS"
}

function checkout_opus() {
  echo "$PRE Checking out OPUS ${OPUS_VERSION}"
  rm -rf "${SOURCE_DIR}/opus"
  mkdir -p "${SOURCE_DIR}/opus"
  curl -o /tmp/opus-${OPUS_VERSION}.tar.gz -LO http://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz
  echo /tmp/opus-${OPUS_VERSION}.tar.gz
  tar zxf /tmp/opus-${OPUS_VERSION}.tar.gz --strip 1 -C "${SOURCE_DIR}/opus"
  # git clone https://git.xiph.org/opus.git "${SOURCE_DIR}/opus"
  # cd "${SOURCE_DIR}/opus" && git checkout $OPUS_VERSION
  echo "$PRE Successfully checked out OPUS"
}

function compile_opus() {
  FOR_ARCHS="${1:-armv7 armv7s arm64 i386 x86_64}"
  echo "$PRE Compiling OPUS for architectures $FOR_ARCHS"

  # Prepare the build directory
  mkdir -p "${BUILD_DIR}/opus/staging/"

  # Copy the PJSIP site config to the target directory
  # cp "${CONFIG_DIR}/pjsip.h" "${SOURCE_DIR}/pjsip/pjlib/include/pj/"
  cd "${SOURCE_DIR}/opus"

  # Compile for each of the requested architectures
  # ls -al ${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${IOS_SDK_VERSION}.sdk
  for CURRENT_ARCH in $FOR_ARCHS; do
    echo "$PRE Compiling OPUS for $CURRENT_ARCH"
    mkdir -p "${BUILD_DIR}/opus/staging/${CURRENT_ARCH}"

    _exports_opus $CURRENT_ARCH
    ./configure --enable-float-approx --disable-shared --enable-static --with-pic --disable-extra-programs --disable-doc ${EXTRA_CONFIG} \
      --prefix=${BUILD_DIR}/opus/staging/${CURRENT_ARCH}
      LDFLAGS="$LDFLAGS ${OPT_LDFLAGS} -fPIE -miphoneos-version-min=${MIN_IOS_VERSION} -L${BUILD_DIR}/opus/lib" \
      CFLAGS="$CFLAGS ${EXTRA_CFLAGS} ${OPT_CFLAGS} -fPIE -miphoneos-version-min=${MIN_IOS_VERSION} -I${BUILD_DIR}/opus/include -isysroot ${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer/SDKs/${PLATFORM}${IOS_SDK_VERSION}.sdk"

    make clean
    make -j4
    make install

    # Copy the headers out to the target directory
    rm -rf "${BUILD_DIR}/opus/include"
    cp -r ${BUILD_DIR}/opus/staging/${CURRENT_ARCH}/include/ "${BUILD_DIR}/opus/include"
  done

  echo "$PRE Successfully compiled OPUS for all architectures"
}

function lipo_opus() {
  echo "$PRE Creating multiarch OPUS binary"
  mkdir -p "${BUILD_DIR}/opus/lib"
  libtool -o ${BUILD_DIR}/opus/lib/libOpus.a `find "${BUILD_DIR}/opus/staging/" -name "*.a"`
  echo "$PRE Successfully created multiarch OPUS binary"
}

##-----------------------------------------------------------------------------
## PJSIP
##-----------------------------------------------------------------------------

function _exports_pjsip() {
  if [ "$1" = "i386" ]; then
    export DEVPATH="${DEVELOPER}/Platforms/iPhoneSimulator.platform/Developer"
    export CFLAGS="-O2 -m32 -mios-simulator-version-min=${MIN_IOS_VERSION}"
    export LDFLAGS="-O2 -m32 -mios-simulator-version-min=${MIN_IOS_VERSION}"
  elif [ "$1" = "x86_64" ]; then
    export DEVPATH="${DEVELOPER}/Platforms/iPhoneSimulator.platform/Developer"
    export CFLAGS="-O2 -m32 -mios-simulator-version-min=${MIN_IOS_VERSION}"
    export LDFLAGS="-O2 -m32 -mios-simulator-version-min=${MIN_IOS_VERSION}"
  else
    unset DEVPATH
    unset CFLAGS
    unset LDFLAGS
  fi
}

function clean_pjsip() {
  echo "$PRE Cleaning PJSIP"
  rm -rf $SOURCE_DIR/pjsip
  rm -rf $BUILD_DIR/pjsip
  echo "$PRE Successfully cleaned PJSIP"
}

function checkout_pjsip() {
  BASE_URL="http://svn.pjsip.org/repos/pjproject"

  echo "$PRE Checking out PJSIP ${PJSIP_VERSION}"
  if [ "$PJSIP_VERSION" = "trunk" ]; then
      CHECKOUT_URL="${BASE_URL}/trunk"
  else
      CHECKOUT_URL="${BASE_URL}/tags/${PJSIP_VERSION}/"
  fi

  rm -rf "$SOURCE_DIR/pjsip"
  svn export "${CHECKOUT_URL}" "$SOURCE_DIR/pjsip"
  echo "$PRE Successfully checked out PJSIP"
}

function compile_pjsip() {
  FOR_ARCHS="${1:-armv7 armv7s arm64 i386 x86_64}"
  echo "$PRE Compiling PJSIP for architectures $FOR_ARCHS"

  # Prepare the build directory
  mkdir -p "${BUILD_DIR}/pjsip/staging/"

  # Copy the PJSIP site config to the target directory
  cp "${CONFIG_DIR}/pjsip.h" "${SOURCE_DIR}/pjsip/pjlib/include/pj/config_site.h"
  cd "${SOURCE_DIR}/pjsip"

  # Compile for each of the requested architectures
  for CURRENT_ARCH in $FOR_ARCHS; do
    echo "$PRE Compiling PJSIP for $CURRENT_ARCH"
    mkdir -p "${BUILD_DIR}/pjsip/staging/${CURRENT_ARCH}"

    _exports_pjsip $CURRENT_ARCH
    ARCH="-arch $CURRENT_ARCH" $SOURCE_DIR/pjsip/configure-iphone --with-opus="${BUILD_DIR}/opus"
    RC=$?

    # Make the project
    make dep
    make clean
    make

    # Copy static libraries into the build directory
    for LIB in `find "${SOURCE_DIR}/pjsip" -name "*$CURRENT_ARCH-apple-darwin_ios.a"`; do
      cp $LIB "${BUILD_DIR}/pjsip/staging/$CURRENT_ARCH/"
    done

    echo "$PRE Successfully compiled PJSIP for $CURRENT_ARCH"
  done

  echo "$PRE Successfully compiled PJSIP for all architectures"
}

function lipo_pjsip() {
  echo "$PRE Creating multiarch PJSIP binary"
  mkdir -p "${BUILD_DIR}/pjsip/lib"
  libtool -o ${BUILD_DIR}/pjsip/lib/libPjsip.a `find "${BUILD_DIR}/pjsip/staging/" -name "*.a"`
  echo "$PRE Successfully created multiarch PJSIP binary"
}

function headers_pjsip() {
  echo "$PRE Copying PJSIP headers"
  mkdir -p "${BUILD_DIR}/pjsip/include"
  BASE_DIR="${SOURCE_DIR}/pjsip/"
  for HEADER in `find "${BASE_DIR}" \
    -path "${BASE_DIR}/third_party" -prune -o \
    -path "${BASE_DIR}/pjsip-apps" -prune -o \
    -path "${BASE_DIR}/include" -prune -o \
    -type f -wholename '*include/*.h*' \
    | grep -v third_party \
    | grep -v pjsip-apps`; do
      SIMPLE_NAME=$(echo "$HEADER" | cut -b $((${#BASE_DIR}+1))- | sed -e 's/.*\/include\/\(.*\)/\/\1/')
      DESTINATION="${BUILD_DIR}/pjsip/include/${SIMPLE_NAME}"
      mkdir -p $(dirname $DESTINATION)
      cp $HEADER $DESTINATION
  done
  echo "$PRE Successfully copied PJSIP headers"
}

##-----------------------------------------------------------------------------
## Global
##-----------------------------------------------------------------------------

function pjsip() {
  clean_pjsip
  checkout_pjsip
  compile_pjsip $ARCH
  lipo_pjsip
  headers_pjsip
}

function opus() {
  clean_opus
  checkout_opus
  compile_opus $ARCH
  lipo_opus
}

function all() {
  opus
  pjsip
}

##-----------------------------------------------------------------------------
## Entry Point
##-----------------------------------------------------------------------------

if [ -n "$1" ]; then
    echo "$PRE Build started"
    CMD=$1
    shift
    $CMD $*
    echo "$PRE Done"
else
    help
fi
