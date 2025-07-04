#!/bin/bash
source .venv/bin/activate
git submodule status
export ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb
export GNUARMEMB_TOOLCHAIN_PATH=/tmp/arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-eabi/
REFERENCE_PLATFORM=ncs REFERENCE_RELEASE_TYPE=1.4 ./script/make-reference-dongle.bash

