#!/usr/bin/env bash
# パッチを当てた Wine の Unix 側のライブラリ(win32u.so、winex11.so)を、再現できる形でビルドする。
#
# 使い方: wine/build-unix.sh [WINE_VERSION]
#   AlmaLinux 8(glibc 2.28)のコンテナ(podman か docker)で、Wine の公式のソースに wine/patches/unix/ のパッチを
#   当て、Unix 側のライブラリだけをビルドする。結果は $CLISTUX_CACHE/unix-build/wine-<版>/ に置く。
#   古い glibc を使うのは、置き換える先の Wine のビルド(Kron4ek)と同じく、多くのディストリビューションで動かすため。
#
# 作者が以前に COSMIC 向けの修正のために書いたビルドスクリプトを下敷きにした。
set -euo pipefail

WINE_VERSION="${1:-11.4}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="$HERE/patches/unix"
CACHE="${CLISTUX_CACHE:-$HOME/.cache/clistux}"
OUT_DIR="$CACHE/unix-build/wine-$WINE_VERSION"
IMAGE="docker.io/library/almalinux:8"

# 当てる順番は patches/unix/series に書く(wine/build.sh と同じ)
PATCHES=()
while read -r p; do
    [[ -z "$p" || "$p" == \#* ]] && continue
    PATCHES+=("$p")
done < "$PATCH_DIR/series"

if command -v podman >/dev/null 2>&1; then
    CTR=podman
elif command -v docker >/dev/null 2>&1; then
    CTR=docker
else
    echo "エラー: podman か docker が必要です" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

# CTR_GLOBAL_OPTS / CTR_RUN_OPTS: カーネルの更新後で再起動前など、overlay や tun が使えないときの回避に使う。
#   例: CTR_GLOBAL_OPTS="--storage-driver=vfs" CTR_RUN_OPTS="--network=host" wine/build-unix.sh
# shellcheck disable=SC2086
"$CTR" ${CTR_GLOBAL_OPTS:-} run ${CTR_RUN_OPTS:-} --rm -i \
    -v "$PATCH_DIR:/patches:ro,z" \
    -v "$OUT_DIR:/out:z" \
    -e WINE_VERSION="$WINE_VERSION" \
    -e PATCHES="${PATCHES[*]}" \
    "$IMAGE" bash -euo pipefail -s << 'BUILD'
dnf -y -q install dnf-plugins-core >/dev/null
dnf config-manager --set-enabled powertools
dnf -y -q install gcc make flex bison patch xz curl \
    libX11-devel libXext-devel libXi-devel libXrandr-devel libXinerama-devel \
    libXcursor-devel libXcomposite-devel libXfixes-devel libXrender-devel \
    libXxf86vm-devel mesa-libGL-devel mesa-libEGL-devel vulkan-loader-devel \
    freetype-devel fontconfig-devel >/dev/null

major="${WINE_VERSION%%.*}"
cd /tmp
curl -fsSL "https://dl.winehq.org/wine/source/${major}.x/wine-${WINE_VERSION}.tar.xz" | tar -xJ
cd "wine-${WINE_VERSION}"
for p in $PATCHES; do
    echo "applying $p"
    patch -p1 < "/patches/$p"
done

mkdir build && cd build
../configure --enable-win64 --without-mingw --disable-tests \
    --without-wayland --without-gstreamer --without-oss --without-pcsclite \
    --without-sane --without-gphoto --without-cups --without-capi \
    --without-krb5 --without-netapi > configure.log 2>&1 \
    || { tail -40 configure.log; exit 1; }

# 置き換えるライブラリは、元のビルドの機能をすべて持っている必要がある:
# 筆圧(XInput2)、モニター(XRandR)、GL/EGL/Vulkan、フォント(FreeType/fontconfig)
for f in HAVE_X11_EXTENSIONS_XINPUT2_H HAVE_X11_EXTENSIONS_XRANDR_H HAVE_LIBXSHAPE \
         HAVE_X11_EXTENSIONS_XSHM_H SONAME_LIBXCOMPOSITE SONAME_LIBGL SONAME_LIBEGL \
         SONAME_LIBVULKAN SONAME_LIBFREETYPE SONAME_LIBFONTCONFIG; do
    grep -q "#define $f" include/config.h || { echo "missing: $f" >&2; exit 1; }
done

make -j"$(nproc)" dlls/winex11.drv/winex11.so dlls/win32u/win32u.so > make.log 2>&1 \
    || { tail -40 make.log; exit 1; }
for lib in dlls/winex11.drv/winex11.so dlls/win32u/win32u.so; do
    strip --strip-unneeded "$lib"
    install -m 644 "$lib" "/out/$(basename "$lib")"
    echo "built: $(basename "$lib") (wine-${WINE_VERSION})"
done
BUILD

ls -la "$OUT_DIR"/winex11.so "$OUT_DIR"/win32u.so
