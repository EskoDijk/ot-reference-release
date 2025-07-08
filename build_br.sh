#!/bin/bash
# Script to activate the Python virtual env and build the OTBR.
# Note: ./bootstrap.sh must be run before the first time build.

set -euox pipefail

activate_python_venv()
{
    if [[ ! -d .venv ]]; then
        python3 -m venv .venv
    fi
    # shellcheck source=/dev/null
    source .venv/bin/activate
}

activate_python_venv

git submodule status
export ZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb
export GNUARMEMB_TOOLCHAIN_PATH=/tmp/arm-gnu-toolchain-14.2.rel1-x86_64-arm-none-eabi/
REFERENCE_PLATFORM=ncs REFERENCE_RELEASE_TYPE=1.4 ./script/make-reference-release.bash
