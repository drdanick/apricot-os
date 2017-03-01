#!/bin/sh

APRICOSASM_CMD="java -jar ${PWD}/apricosasm.jar"

mkdir build
pushd src

$APRICOSASM_CMD ../src/boot.asm && mv -f boot.bin ../build/

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
    testprogram.asm \
    && mv -f link.bin ../build/0.dsk && mv -f symbols.sym ../build/

popd
