#!/bin/bash
#
#  Copyright (c) 2021, The OpenThread Authors.
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#  3. Neither the name of the copyright holder nor the
#     names of its contributors may be used to endorse or promote products
#     derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
#  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.
#

set -euxo pipefail

if [[ -n ${BASH_SOURCE[0]} ]]; then
    script_path="${BASH_SOURCE[0]}"
else
    script_path="$0"
fi

script_dir="$(dirname "$(realpath "$script_path")")"
repo_dir="$(dirname "$script_dir")"

# Global Vars
platform=""
build_dir=""
build_script_flags=()
NRFUTIL=""

readonly build_1_4_options_common=(
    "-DOT_THREAD_VERSION=1.4"
    "-DOT_SRP_SERVER=ON"
    "-DOT_ECDSA=ON"
    "-DOT_SERVICE=ON"
    "-DOT_DNSSD_SERVER=ON"
    "-DOT_SRP_CLIENT=ON"
)

readonly build_1_4_options_nrf=(
    ""
)

readonly build_1_3_options_common=(
    "-DOT_THREAD_VERSION=1.3"
    "-DOT_SRP_SERVER=ON"
    "-DOT_ECDSA=ON"
    "-DOT_SERVICE=ON"
    "-DOT_DNSSD_SERVER=ON"
    "-DOT_SRP_CLIENT=ON"
)

readonly build_1_3_options_nrf=(
    ""
)

readonly build_1_2_options_common=(
    '-DOT_THREAD_VERSION=1.2'
    '-DOT_REFERENCE_DEVICE=ON'
    '-DOT_BORDER_ROUTER=ON'
    '-DOT_SERVICE=ON'
    '-DOT_COMMISSIONER=ON'
    '-DOT_JOINER=ON'
    '-DOT_MAC_FILTER=ON'
    '-DOT_DHCP6_SERVER=ON'
    '-DOT_DHCP6_CLIENT=ON'
    '-DOT_DUA=ON'
    '-DOT_MLR=ON'
    '-DOT_LINK_METRICS_INITIATOR=ON'
    '-DOT_LINK_METRICS_SUBJECT=ON'
    '-DOT_CSL_RECEIVER=ON'
    '-DOT_BORDER_AGENT=OFF'
    '-DOT_COAP=OFF'
    '-DOT_COAPS=OFF'
    '-DOT_ECDSA=OFF'
    '-DOT_FULL_LOGS=OFF'
    '-DOT_IP6_FRAGM=OFF'
    '-DOT_LINK_RAW=OFF'
    '-DOT_NETDIAG_CLIENT=OFF'
    '-DOT_SNTP_CLIENT=OFF'
    '-DOT_UDP_FORWARD=OFF'
)

readonly build_1_2_options_nrf=(
    '-DOT_BOOTLOADER=USB'
    '-DOT_CSL_RECEIVER=ON'
)

readonly build_1_1_env_common=(
    'BORDER_ROUTER=1'
    'REFERENCE_DEVICE=1'
    'COMMISSIONER=1'
    'DHCP6_CLIENT=1'
    'DHCP6_SERVER=1'
    'JOINER=1'
    'MAC_FILTER=1'
    'BOOTLOADER=USB'
)

readonly build_1_1_env_nrf=(
    'USB=1'
)

# Args
# - $1: The name of the hex file to zip
# - $2: The basename of the file
# - $3: Thread version number, e.g. 1.2
# - $4: Timestamp
# - $5: Commit ID
distribute()
{
    local hex_file=$1
    local zip_file="$2-$3-$4-$5.zip"

    case "${platform}" in
        nrf* | ncs*)
            ${NRFUTIL} pkg generate --debug-mode --hw-version 52 --sd-req 0 --application "${hex_file}" --key-file /tmp/private.pem "${zip_file}"
            ;;
        *)
            zip "${zip_file}" "${hex_file}"
            ;;
    esac

    mv "${zip_file}" "$OUTPUT_ROOT"
}

# Environment Vars
# - $thread_version: Thread version number, e.g. 1.2
# Args
# - $1: The basename of the file to zip, e.g. ot-cli-ftd
# - $2: The binary path (optional)
package_ot()
{
    # Parse Args
    local basename=${1?Please specify app basename}
    local binary_path=${2:-"${build_dir}/bin/${basename}"}
    thread_version=${thread_version?}

    # Get build info
    local commit_id
    local timestamp
    commit_id=$(cd "${repo_dir}"/openthread && git rev-parse --short HEAD)
    timestamp=$(date +%Y%m%d)

    # Generate .hex file
    local hex_file="${basename}"-"${thread_version}".hex
    if [ ! -f "$binary_path" ]; then
        echo "WARN: $binary_path does not exist. Skipping packaging"
        return
    fi
    arm-none-eabi-objcopy -O ihex "$binary_path" "${hex_file}"

    # Distribute
    distribute "${hex_file}" "${basename}" "${thread_version}" "${timestamp}" "${commit_id}"
}

# Envionment variables:
# - build_type:             Type of build (optional)
# - build_script_flags:     Any flags specific to the platform repo's build script (optional)
# Args:
# - $1 - thread_version: Thread version number, e.g. 1.2
# - $2 - platform_repo:  Path to platform's repo, e.g. ot-efr32, ot-nrf528xx
build_ot()
{
    thread_version=${thread_version?}
    platform_repo=${platform_repo?}

    mkdir -p "$OUTPUT_ROOT"

    case "${thread_version}" in
        "1.2"|"1.3"|"1.4")
            # Build OpenThread 1.2 or 1.3 or 1.4
            cd "${platform_repo}"
            git clean -xfd

            # Use OpenThread from top-level of repo
            rm -rf openthread
            # git_archive_all doesn't accept symbolic link, so make a copy of openthread and make
            # it not a submodule
            cp -rp ../openthread .
            rm openthread/.git

            # Build
            build_dir=${OT_CMAKE_BUILD_DIR:-"${repo_dir}"/build-"${thread_version}"/"${platform}"}

            if [ -z "${build_script_flags[@]}" ]; then
                OT_CMAKE_BUILD_DIR="${build_dir}" ./script/build "${platform}" "${build_type:-}" "$@"
            else
                OT_CMAKE_BUILD_DIR="${build_dir}" ./script/build "${build_script_flags[@]}" "${platform}" "${build_type:-}" "$@"
            fi

            # Package and distribute
            local dist_apps=(
                ot-cli-ftd
                ot-rcp
            )
            for app in "${dist_apps[@]}"; do
                package_ot "${app}"
            done

            # Clean up
            git clean -xfd
            ;;
        "1.1")
            # Build OpenThread 1.1
            cd openthread-1.1

            # Prep
            git clean -xfd
            ./bootstrap

            # Build
            make -f examples/Makefile-"${platform}" "${options[@]}"

            # Package and distribute
            local dist_apps=(
                ot-cli-ftd
                ot-rcp
            )
            for app in "${dist_apps[@]}"; do
                package_ot "${app}" "${thread_version}" output/"${platform}"/bin/"${app}"
            done

            # Clean up
            git clean -xfd
            ;;
    esac

    cd "${repo_dir}"
}

die()
{
    echo "$*" 1>&2
    exit 1
}

nrfutil_setup()
{
    # Setup nrfutil
    if [[ $OSTYPE == "linux"* ]]; then
        ostype=unknown-linux-gnu
        arch=x86_64
    elif [[ $OSTYPE == "darwin"* ]]; then
        ostype=apple-darwin
        arch=$(uname -m)
    fi
    NRFUTIL=/tmp/nrfutil-${ostype}-${arch}

    if [ ! -f $NRFUTIL ]; then
        wget -O $NRFUTIL https://files.nordicsemi.com/ui/api/v1/download?repoKey=swtools\&path=external/nrfutil/executables/${arch}-${ostype}/nrfutil
        chmod +x $NRFUTIL
    fi

    $NRFUTIL install nrf5sdk-tools

    # Generate private key
    if [ ! -f /tmp/private.pem ]; then
        $NRFUTIL keys generate /tmp/private.pem
    fi
}

deploy_ncs()
{
    local commit_hash
    commit_hash=$(<"${script_dir}"'/../config/ncs/sdk-nrf-commit')

    sudo apt install --no-install-recommends git cmake ninja-build gperf \
        ccache dfu-util device-tree-compiler wget \
        python3-dev python3-pip python3-setuptools python3-tk python3-wheel xz-utils file \
        make gcc gcc-multilib g++-multilib libsdl2-dev
    pip3 install west
    mkdir -p "${script_dir}"/../ncs
    cd "${script_dir}"/../ncs
    unset ZEPHYR_BASE
    west init -m https://github.com/nrfconnect/sdk-nrf --mr main || true
    cd nrf
    git fetch origin
    git reset --hard "$commit_hash" || die "ERROR: unable to checkout the specified sdk-nrf commit."
    west update -n -o=--depth=1
    cd ..

    if [[ -n ${OPENTHREAD_COMMIT_HASH:=} ]]; then
        echo "Using custom OT SHA: ${OPENTHREAD_COMMIT_HASH?}"
        cd modules/lib/openthread
        # remove remote if exists to make clean repository
        if git remote | grep -q openthread; then
            git remote remove openthread
        fi
        git remote add openthread https://github.com/openthread/openthread.git
        git fetch openthread "$OPENTHREAD_COMMIT_HASH"
        git checkout FETCH_HEAD || die "ERROR: unable to checkout the specified openthread commit."
        cd ../../../
    fi

    pip3 install -r zephyr/scripts/requirements.txt
    pip3 install -r nrf/scripts/requirements.txt
    pip3 install -r bootloader/mcuboot/scripts/requirements.txt

    # shellcheck disable=SC1091
    source zephyr/zephyr-env.sh
    west config manifest.path nrf
}

build_ncs()
{
    mkdir -p "$OUTPUT_ROOT"
    deploy_ncs
    cd nrf

    thread_version=${thread_version?}
    local timestamp=$(date +%Y%m%d)
    local commit_id=$(git rev-parse --short HEAD)

    # variant is a list of entries: "app:sample_name"
    local variants
    case "${thread_version}" in
        1.1)
            variants=("ot-cli-ftd:cli")
            ;;
        *)
            variants=("ot-cli-ftd:cli" "ot-rcp:coprocessor")
            ;;

    esac

    for variant in "${variants[@]}"; do
        local app=$(echo $variant | cut -d':' -f1)
        local sample_name=$(echo $variant | cut -d':' -f2)
        local sample_path="samples/openthread/${sample_name}"
        local sample_config_path="${script_dir}/../config/ncs/overlay"
        local sample_config="${sample_config_path}-common.conf;${sample_config_path}-${app}-common.conf;${sample_config_path}-${app}-${thread_version}.conf"
        local build_path="/tmp/ncs_${app}_${thread_version}"
        local hex_path="${build_path}/${sample_name}/zephyr/zephyr.hex"

        west build -d "${build_path}" -b nrf52840dongle/nrf52840 -p always "${sample_path}" --sysbuild -- -DOVERLAY_CONFIG="${sample_config}"

        distribute "${hex_path}" "${app}" "${thread_version}" "${timestamp}" "${commit_id}"
    done
}

build()
{
    if [ "${REFERENCE_RELEASE_TYPE?}" = "1.2" ]; then
        build_1_2_options=("${build_1_2_options_common[@]}")
        build_1_1_env=("${build_1_1_env_common[@]}")

        case "${platform}" in
            nrf*)
                build_1_2_options+=("${build_1_2_options_nrf[@]}")
                build_1_1_env+=("${build_1_1_env_nrf[@]}")
                platform_repo=ot-nrf528xx

                thread_version=1.2 build_type="USB_trans" build_ot "${build_1_2_options[@]}" "$@"
                thread_version=1.1 build_type="USB_trans" build_ot "${build_1_1_env[@]}" "$@"
                ;;
            ncs)
                thread_version=1.2 build_ncs
                thread_version=1.1 build_ncs
                ;;
        esac
    elif [ "${REFERENCE_RELEASE_TYPE}" = "1.3" ]; then
        options=("${build_1_3_options_common[@]}")

        case "${platform}" in
            nrf*)
                options+=("${build_1_3_options_nrf[@]}")
                platform_repo=ot-nrf528xx

                thread_version=1.3 build_type="USB_trans" build_ot "${options[@]}" "$@"
                ;;
            efr32mg12)
                platform_repo=ot-efr32
                build_script_flags=("--skip-silabs-apps")
                thread_version=1.3 build_ot "-DBOARD=brd4166a" "${options[@]}" "$@"
                ;;
            ncs)
                thread_version=1.3 build_ncs
                ;;
        esac
    elif [ "${REFERENCE_RELEASE_TYPE}" = "1.4" ]; then
        options=("${build_1_4_options_common[@]}")

        case "${platform}" in
            nrf*)
                options+=("${build_1_4_options_nrf[@]}")
                platform_repo=ot-nrf528xx

                thread_version=1.4 build_type="USB_trans" build_ot "${options[@]}" "$@"
                ;;
            efr32mg12)
                platform_repo=ot-efr32
                build_script_flags=("--skip-silabs-apps")
                thread_version=1.4 build_ot "-DBOARD=brd4166a" "${options[@]}" "$@"
                ;;
            ncs)
                thread_version=1.4 build_ncs
                ;;
        esac
    else
        die "Error: REFERENCE_RELEASE_TYPE = ${REFERENCE_RELEASE_TYPE} is unsupported"
    fi
}

main()
{
    readonly OT_PLATFORMS=(nrf52840 efr32mg12 ncs)

    local platforms=()

    if [[ $# == 0 ]]; then
        platforms=("${OT_PLATFORMS[@]}")
    else
        platforms=("$1")
        shift
    fi

    # Print OUTPUT_ROOT. Error if OUTPUT_ROOT is not defined
    OUTPUT_ROOT=$(realpath "${OUTPUT_ROOT?}")
    echo "OUTPUT_ROOT=${OUTPUT_ROOT}"
    mkdir -p "${OUTPUT_ROOT}"

    for p in "${platforms[@]}"; do
        # Check if the platform is supported.
        echo "${OT_PLATFORMS[@]}" | grep -wq "${p}" || die "ERROR: Unsupported platform: ${p}"
        printf "\n\n======================================\nBuilding firmware for %s\n======================================\n\n" "${p}"
        platform=${p}
        case "${platform}" in
            nrf* | ncs*)
                nrfutil_setup
                ;;
        esac

        build "$@"
    done

}

main "$@"
