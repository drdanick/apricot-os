#!/bin/sh

#
# NOTE: This script must be run from the project root!
#


# The Apricos Assembler jar must be placed in the project root.
# It can be obtained from https://github.com/drdanick/apricosasm-java/releases
#
APRICOSASM_CMD="java -jar ${PWD}/apricosasm.jar"
PROJECT_ROOT=$PWD
BUILD_DIR="${PROJECT_ROOT}/build"

mkdir $BUILD_DIR
pushd src

$APRICOSASM_CMD -s boot.asm && mv -f boot.bin $BUILD_DIR && mv -f symbols.sym $BUILD_DIR/boot.sym && \
$APRICOSASM_CMD -lds \
    diskio.asm \
    diskalloc.asm \
    disp.asm \
    faulthandler.asm \
    memutil.asm \
    osutil.asm \
    s2boot.asm \
    shell.asm \
    shellcmds.asm \
    shellmem.asm \
    shellutil.asm \
    osinit.asm \
    math.asm \
    fsdriver.asm \
    fsmem.asm \
    testprogram.asm \
    && mv -f link.bin ${BUILD_DIR}/0.dsk && mv -f symbols.sym $BUILD_DIR

popd
