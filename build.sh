#!/bin/bash

export BASE_DIR=`pwd -P`
export PRODUCT_NAME='libPjsip'
export TARGET_DIR='vendor'

cd `dirname $BASH_SOURCE`

set -o errexit
set -o errtrace

export PRE=" ───── "

function help() {
cat <<EOF
$0 help          # shows this help message.
$0 svn_checkout  # Get the latest PJSIP sources from SVN
$0 clean         # cleans the pjsip source folder.
$0 all           # build fat binary that works on all architectures.
$0 armv7         # build armv7 static lib.
$0 armv7s        # build armv7s static lib.
$0 arm64         # build arm64 static lib.
$0 i386          # build i386 static lib.
$0 x86_64        # build x86_64 static lib.
$0 info armv7    # show architecture information for armv7 libs.
$0 info armv7s   # show architecture information for armv7s libs.
$0 info arm64    # show architecture information for arm64 libs.
$0 info i386     # show architecture information for i386 libs.
$0 info x86_64   # show architecture information for x86_64 libs.
$0 complete	  # Downloads, builds and copies files.
EOF
}

function complete() {
    clean
    svn_checkout $1
    mkdir -p "$BASE_DIR"/pjsip/logs/
    all
    copy_headers
}

function clean() {
    echo "$PRE CLEAN"
    echo "WARNING: About to clean directory: $BASE_DIR/pjsip"
    echo "WARNING: About to clean directory: $BASE_DIR/${TARGET_DIR}"
    echo "waiting 5 seconds for sanity check... CTRL-C to abort now"
    sleep 1 && echo "4..." && \
    sleep 1 && echo "3..." && \
    sleep 1 && echo "2..." && \
    sleep 1 && echo "1..." && \
    sleep 1

    rm -rf "$BASE_DIR/pjsip/"
    rm -rf "$BASE_DIR/${TARGET_DIR}/"
}

# Checks out the supplied PJSIP version source from SVN. If no version provided latest version is used.
function svn_checkout() {
    BASE_URL="http://svn.pjsip.org/repos/pjproject"

    if [ -z ${1} ]; then
        echo "No version provided, checking out \"trunk\""
        CHECKOUT_URL="${BASE_URL}/trunk/"
    else
        echo "Checking out version ${1}"
        CHECKOUT_URL="${BASE_URL}/tags/${1}/"
    fi

    if [ ! -d "${BASE_DIR}/src/" ]; then
        # Src does not exist, assuming no previous version downloaded, using checkout.
        svn export "${CHECKOUT_URL}" pjsip/src/
        # Svn checkout http://svn.pjsip.org/repos/pjproject/tags/2.2.1/ src/
    else
        # Src directory exists, using switch to prevent 'is already a working copy for a different URL' error.
        svn switch "${CHECKOUT_URL}" pjsip/src/
    fi
}

# Function Prints info about the created libraries.
function info() {
    echo "$PRE ARCH"
    find ${TARGET_DIR}/$1/*.a | \
    xargs lipo -info 2>/dev/null | grep "rchitecture" | \
    sed -El "s/^.+\: .+\/(.+) (are|is architecture)\: (.+)$/\\3 - \\1/g" | \
    sort

    echo
    echo "$PRE INCLUDES"
    find src | grep "\\include$" | sort
}

# Shortcut function for building armv7 lib
function armv7() { _build "armv7"; }
# Shortcut function for building armv7s lib
function armv7s() { _build "armv7s"; }
# Shortcut function for building arm64 lib
function arm64() { _build "arm64"; }

# Shortcut function for building i386 lib
function i386() {
    export DEVPATH=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer
    export CFLAGS="-O2 -m32 -mios-simulator-version-min=9.0"
    export LDFLAGS="-O2 -m32 -mios-simulator-version-min=9.0"
    _build "i386"
}

# Shortcut function for building x86_64 lib
function x86_64() {
    export DEVPATH=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer
    export CFLAGS="-O2 -m32 -mios-simulator-version-min=9.0"
    export LDFLAGS="-O2 -m32 -mios-simulator-version-min=9.0"
    _build "x86_64"
}

# Shortcut function for building all architectures.
function all() {
    armv7 && echo && armv7s && echo && arm64 && echo && i386 && echo && x86_64
    echo
    _merge
}

# Build function doing the actual library building for the specific architecture
function _build() {
    echo "$PRE BUILD"
    echo "building for $1. this may take a while, tail -f $1.log to see progress."
    echo ""

    cp "$BASE_DIR"/config_site.h "$BASE_DIR"/pjsip/src/pjlib/include/pj
    cd "$BASE_DIR"/pjsip/src
    ARCH="-arch $1" ./configure-iphone 2>&1 > "$BASE_DIR"/pjsip/logs/$1.log

    make dep 2>&1 >> "$BASE_DIR"/pjsip/logs/$1.log
    make clean 2>&1 >> "$BASE_DIR"/pjsip/logs/$1.log
    make 2>&1 >> "$BASE_DIR"/pjsip/logs/$1.log

    echo
    _collect $1
}

# The _build function's output is always stored in the same location causing files to be overridden when another architecture is build.
# This function collects the architecture specific build files and stores them in an appropriate directory.
function _collect() {
    echo "$PRE COLLECT"
    cd "$BASE_DIR"
    mkdir -p pjsip/temp/$1

    #for x in `find src | grep "\.a$"`; do
    for x in `find pjsip/src -name *$1*.a`; do
        cp -v ./$x ./pjsip/temp/$1
    done | tee "$BASE_DIR"/pjsip/logs/collect.log
}

# Finds all the created architecture specific libraries, stored by the _collect function and merges all libraries in one fat lib suitable for all architectures.
function _merge() {
    echo "$PRE MERGE"
    cd "$BASE_DIR"

    mkdir -p "$BASE_DIR"/${TARGET_DIR}
    libtool -o ${TARGET_DIR}/${PRODUCT_NAME}.a `find ./pjsip/temp -name *darwin_ios.a -exec printf '%s ' {} +`
    #rm -Rf "$BASE_DIR"/pjsip/temp
}

# Copies header files form the PJSIP src into a temporary directory.
function copy_headers() {
    echo "$PRE Copying header files to temporary location"
    cd "$BASE_DIR"/pjsip/src
    find . -path ./third_party -prune -o -path ./pjsip-apps -prune -o -path ./include -prune -o -type f -wholename '*include/*.h*' -exec bash -c 'copy_to_lib_dir "{}"' ';'
    cd "$BASE_DIR"
}

# helper function used by copy_headers
function copy_to_lib_dir() {
    OLD_PATH=$1
    NEW_PATH=()

    PATH_PARTS=(`echo $1 | tr '/' '\n'`)
    for x in "${PATH_PARTS[@]}"; do
        if [ "$x" = "include" ] || [ "${#NEW_PATH[@]}" -ne "0" ]; then
            NEW_PATH+=("$x")
        fi
    done

    NEW_PATH="${NEW_PATH[@]:1}"
    NEW_PATH="${NEW_PATH// //}"

    d=$BASE_DIR/${TARGET_DIR}/pjsip-include/$(dirname $NEW_PATH)
    mkdir -p $d
    cp $OLD_PATH $d
}

export -f copy_to_lib_dir

if [ -n "$1" ]; then
    CMD=$1
    shift
    $CMD $*

    echo
    echo "$PRE DONE"

else
    help
fi
