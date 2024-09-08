#!/usr/bin/env bash

base=$(dirname "$(readlink -f "$0")")
install=$base/install
src=$base/src
repo_owner="Rv-Trees"
repo_name="RvClang"

set -eu

function parse_parameters() {
    while (($#)); do
        case $1 in
            all | binutils | deps | kernel | llvm | clangversion | createrelease) action=$1 ;;
            *) exit 33 ;;
        esac
        shift
    done
}

function do_all() {
    do_deps
    do_llvm
    do_binutils
    do_clangversion
    do_createrelease
    do_kernel
}

function do_binutils() {
    "$base"/build-binutils.py \
        --install-folder "$install" \
        --show-build-commands \
        --targets x86_64
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
        zlib1g-dev
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
        --assertions \
        --build-stage1-only \
        --build-target distribution \
        --check-targets clang lld llvm \
        --install-folder "$install" \
        --install-target distribution \
        --projects clang lld \
        --quiet-cmake \
        --ref release/17.x \
        --shallow-clone \
        --show-build-commands \
        --targets X86 \
        "${extra_args[@]}"
}

function do_clangversion() {
    clang_version="$("$base"/install/bin/clang --version | head -n1 | cut -d' ' -f4)"
    file="RvClang-$clang_version.tar.gz"
}

function do_createrelease() {
    TAG_NAME="RvClang-$clang_version-$(date +'%Y%m%d')"
    RELEASE_NAME="$TAG_NAME"
    RELEASE_BODY="$TAG_NAME"

    if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
        echo "Tag $TAG_NAME already exists"
    else
        git tag "$TAG_NAME"
        git push origin "$TAG_NAME"
    fi

    RELEASE_RESPONSE=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -d "{\"tag_name\":\"$TAG_NAME\", \"target_commitish\":\"main\", \"name\":\"$RELEASE_NAME\", \"body\":\"$RELEASE_BODY\", \"draft\":false, \"prerelease\":false}" \
        "https://api.github.com/repos/$repo_owner/$repo_name/releases")

    RELEASE_ID=$(echo "$RELEASE_RESPONSE" | jq -r '.id')

    if [ "$RELEASE_ID" == "null" ] || [ -z "$RELEASE_ID" ]; then
        echo "Failed to create release"
        echo "Response: $RELEASE_RESPONSE"
        exit 1
    else
        echo "Release created successfully with ID: $RELEASE_ID"
    fi
}


parse_parameters "$@"
do_"${action:=all}"
