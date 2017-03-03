#!/bin/sh

#
# NOTE: This script must be run from the project root!
#


# The Apricos Assembler jar must be placed in the project root.
# It can be obtained from https://github.com/drdanick/apricosasm-java/releases
#
APRICOSASM_CMD="java -jar ${PWD}/apricosasm.jar"
PROJECT_ROOT=$PWD

mkdir build
pushd src

$APRICOSASM_CMD boot.asm && mv -f boot.bin ${PROJECT_ROOT}/build/

$APRICOSASM_CMD -lds \
    diskio.asm \
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
    && mv -f link.bin ${PROJECT_ROOT}/build/0.dsk && mv -f symbols.sym ${PROJECT_ROOT}/build/

popd
