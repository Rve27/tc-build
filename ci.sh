#!/usr/bin/env bash

base=$(dirname "$(readlink -f "$0")")
install=$base/RvClang
src=$base/src

set -eu

function parse_parameters() {
    while (($#)); do
        case $1 in
            all | binutils | deps | kernel | llvm) action=$1 ;;
            *) exit 33 ;;
        esac
        shift
    done
}

function do_all() {
    do_deps
    do_llvm
    do_binutils
    do_kernel
}

function do_binutils() {
    "$base"/build-binutils.py \
        --install-folder "$install" \
        --targets arm aarch64 x86_64
}

function do_deps() {
    # We only run this when running on GitHub Actions
    [[ -z ${GITHUB_ACTIONS:-} ]] && return 0

    sudo apt-get install -y --no-install-recommends \
        bc \
        bison \
        ca-certificates \
        clang \
        cmake \
        curl \
        file \
        flex \
        gcc \
        g++ \
        git \
        libelf-dev \
        libssl-dev \
        lld \
        make \
        ninja-build \
        python3 \
        texinfo \
        xz-utils \
        zlib1g-dev \
	zip \
	tar
}

function do_kernel() {
    local branch=linux-rolling-stable
    local linux=$src/$branch

    if [[ -d $linux ]]; then
        git -C "$linux" fetch --depth=1 origin $branch
        git -C "$linux" reset --hard FETCH_HEAD
    else
        git clone \
            --branch "$branch" \
            --depth=1 \
            --single-branch \
            https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
            "$linux"
    fi

    cat <<EOF | env PYTHONPATH="$base"/tc_build python3 -
from pathlib import Path

from kernel import LLVMKernelBuilder

builder = LLVMKernelBuilder()
builder.folders.build = Path('$base/build/linux')
builder.folders.source = Path('$linux')
builder.matrix = {'defconfig': ['X86']}
builder.toolchain_prefix = Path('$install')

builder.build()
EOF
}

function do_llvm() {
    extra_args=()
    [[ -n ${GITHUB_ACTIONS:-} ]] && extra_args+=(--no-ccache)

    "$base"/build-llvm.py \
        --install-folder "$install" \
	--build-type Release \
	--no-update \
        --quiet-cmake \
        --ref release/19.x \
        --shallow-clone \
        --targets AArch64 ARM X86 \
	--vendor-string Rv \
        "${extra_args[@]}"
}

parse_parameters "$@"
do_"${action:=all}"
