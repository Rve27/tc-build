#!/usr/bin/env bash

base=$(dirname "$(readlink -f "$0")")
install=$base/install
repo_owner="Rv-Trees"
repo_name="RvClang"

set -eu

function parse_parameters() {
    while (($#)); do
        case $1 in
            all | binutils | deps | llvm | clangversion | createrelease | uploadasset) action=$1 ;;
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
    do_uploadasset
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
        zlib1g-dev
}

function do_llvm() {
    extra_args=()
    [[ -n ${GITHUB_ACTIONS:-} ]] && extra_args+=(--no-ccache)

    "$base"/build-llvm.py \
        --build-target distribution \
        --check-targets clang lld llvm \
        --install-folder "$install" \
        --install-target distribution \
        --projects clang lld \
        --quiet-cmake \
        --ref main \
        --shallow-clone \
        --show-build-commands \
        --targets AArch64 ARM X86 \
        --vendor-string "Rv" \
        "${extra_args[@]}"
}

function do_clangversion() {
    clang_version="$("$base"/install/bin/clang --version | head -n1 | cut -d' ' -f4)"
    file="$base/RvClang-$clang_version.tar.gz"
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

function do_uploadasset() {
    if [ -z "$RELEASE_ID" ]; then
        echo "Release ID is missing. Cannot upload asset."
        exit 1
    fi

    if curl -s --data-binary @"$file" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: $(file --mime-type -b "$file")" \
        "https://uploads.github.com/repos/$repo_owner/$repo_name/releases/$RELEASE_ID/assets?name=$(basename "$file")"; then
        echo "Asset uploaded successfully."
    else
        echo "Failed to upload asset."
    fi
}

parse_parameters "$@"
do_"${action:=all}"
