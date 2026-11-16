#!/usr/bin/env bash
# 配布用の Wine を、再現できる形でビルドする。
#
# 使い方: wine/build.sh [WINE_VERSION]
#   Wine の公式のソースに wine/patches/ のパッチを当て、コンテナ(podman か docker)で2段に分けてビルドする。
#   1. Windows の DLL(PE): Debian 12 の mingw-w64 の GCC 12 で作る。clang で作った C のランタイム(ucrtbase など)では、
#      CSP 5.1.5 が起動中に C++ の例外の後始末(__CxxUnregisterExceptionObject)で落ちた(2026-11-15)。
#   2. Linux 側: AlmaLinux 8(glibc 2.28)で作り、Windows の DLL を 1. のものに入れ替えてまとめる。
#   32bit の Windows のプログラム(CSP のインストーラなど)は WoW64 で動かすので、32bit の Linux のライブラリは要らない。
#   結果: $CLISTUX_CACHE/dist/wine-<版>-csp<リビジョン>-x86_64.tar.xz と、その .sha256。
#   古い glibc を使うのは、多くのディストリビューションで動かすため。
#
# 環境変数:
#   CLISTUX_CACHE       置き場所(既定: ~/.cache/clistux)
#   CSP_REVISION     このプロジェクトでのリビジョン(既定: wine/REVISION の値)
#   CTR_GLOBAL_OPTS / CTR_RUN_OPTS  コンテナのコマンドに渡す追加の引数
set -euo pipefail

WINE_VERSION="${1:-11.4}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="${CLISTUX_CACHE:-$HOME/.cache/clistux}"
REVISION="${CSP_REVISION:-$(cat "$HERE/REVISION")}"
NAME="wine-$WINE_VERSION-csp$REVISION-x86_64"
DIST="$CACHE/dist"
IMAGE="docker.io/library/almalinux:8"

if command -v podman >/dev/null 2>&1; then
    CTR=podman
elif command -v docker >/dev/null 2>&1; then
    CTR=docker
else
    echo "エラー: podman か docker が必要です" >&2
    exit 1
fi

# 当てる順番: PE 側(git format-patch の連番)、続いて Unix 側(series に書いた順)
PATCHES=()
for p in "$HERE"/patches/[0-9][0-9][0-9][0-9]-*.patch; do PATCHES+=("$(basename "$p")"); done
while read -r p; do
    [[ -z "$p" || "$p" == \#* ]] && continue
    PATCHES+=("unix/$p")
done < "$HERE/patches/unix/series"

mkdir -p "$DIST"
echo "ビルド: $NAME(パッチ ${#PATCHES[@]} 本)"
PE_OUT="$CACHE/pe-build/$NAME"
rm -rf "$PE_OUT"; mkdir -p "$PE_OUT"

# ---- 1. Windows の DLL(mingw-w64 の GCC) -------------------------------------------
echo "1/2: Windows の DLL をビルドしています(mingw-w64 GCC)"
# shellcheck disable=SC2086
"$CTR" ${CTR_GLOBAL_OPTS:-} run ${CTR_RUN_OPTS:-} --rm -i \
    -v "$HERE/patches:/patches:ro,z" \
    -v "$PE_OUT:/out:z" \
    -e WINE_VERSION="$WINE_VERSION" \
    -e PATCHES="${PATCHES[*]}" \
    docker.io/library/debian:12 bash -euo pipefail -s << 'PEBUILD'
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update
# Linux 側の機能を外すと、対応する Windows 側の DLL(winex11.drv など)も作られないので、2段目と同じ機能を有効にする
apt-get -qq install -y --no-install-recommends gcc libc6-dev gcc-mingw-w64 make flex bison patch xz-utils curl ca-certificates \
    libx11-dev libxext-dev libxi-dev libxrandr-dev libxinerama-dev libxcursor-dev libxcomposite-dev libxfixes-dev \
    libxrender-dev libxxf86vm-dev libgl-dev libegl-dev libvulkan-dev libfreetype-dev libfontconfig-dev \
    libgnutls28-dev libudev-dev libdbus-1-dev libpulse-dev libasound2-dev > /dev/null
x86_64-w64-mingw32-gcc --version | head -1
major="${WINE_VERSION%%.*}"
cd /tmp
curl -fsSL "https://dl.winehq.org/wine/source/${major}.x/wine-${WINE_VERSION}.tar.xz" | tar -xJ
cd "wine-${WINE_VERSION}"
for p in $PATCHES; do patch -p1 --no-backup-if-mismatch < "/patches/$p" > /dev/null; done
mkdir build && cd build
# configure の引数は2段目と同じにする(ここで作った Linux 側のものは使わない)
../configure --prefix=/usr --enable-archs=i386,x86_64 --with-mingw --disable-tests \
    --without-wayland --without-gstreamer --without-ffmpeg --without-oss --without-pcsclite \
    --without-sane --without-gphoto --without-cups --without-capi --without-krb5 \
    --without-netapi --without-v4l2 --without-usb --without-sdl --without-unwind \
    > configure.log 2>&1 || { tail -40 configure.log; exit 1; }
grep -q '^PE_ARCHS = *i386 x86_64' Makefile || { echo "PE のビルドが有効になっていません" >&2; exit 1; }
grep -q '^x86_64_CC = *x86_64-w64-mingw32-gcc' Makefile || { echo "mingw の GCC が使われていません" >&2; grep '^x86_64_CC' Makefile >&2; exit 1; }
make -j"$(nproc)" > make.log 2>&1 || { grep -E 'error' make.log | tail -30; exit 1; }
make install-lib DESTDIR=/tmp/stage > install.log 2>&1 || { tail -30 install.log; exit 1; }
cp -a /tmp/stage/usr/lib/wine/x86_64-windows /tmp/stage/usr/lib/wine/i386-windows /out/
echo "PE: $(ls /out/x86_64-windows | wc -l) + $(ls /out/i386-windows | wc -l) 個"
PEBUILD
[[ -f "$PE_OUT/x86_64-windows/ucrtbase.dll" ]] || { echo "エラー: Windows の DLL のビルドに失敗しました" >&2; exit 1; }

# WebView2 の動作を確かめる道具(wv2check.exe)も、同じ配布ファイルに入れる
"$HERE/../integration/wv2check/build.sh" "$PE_OUT/wv2check" > /dev/null
[[ -f "$PE_OUT/wv2check/wv2check.exe" ]] || { echo "エラー: wv2check のビルドに失敗しました" >&2; exit 1; }

# ---- 2. Linux 側(AlmaLinux 8)とまとめ ------------------------------------------------
echo "2/2: Linux 側をビルドしてまとめています(AlmaLinux 8)"

# shellcheck disable=SC2086
"$CTR" ${CTR_GLOBAL_OPTS:-} run ${CTR_RUN_OPTS:-} --rm -i \
    -v "$HERE/patches:/patches:ro,z" \
    -v "$DIST:/out:z" \
    -v "$PE_OUT:/pe:ro,z" \
    -e WINE_VERSION="$WINE_VERSION" \
    -e NAME="$NAME" \
    -e PATCHES="${PATCHES[*]}" \
    "$IMAGE" bash -euo pipefail -s << 'BUILD'
dnf -y -q install dnf-plugins-core >/dev/null
dnf config-manager --set-enabled powertools
dnf -y -q install gcc make flex bison patch xz curl clang lld llvm \
    libX11-devel libXext-devel libXi-devel libXrandr-devel libXinerama-devel \
    libXcursor-devel libXcomposite-devel libXfixes-devel libXrender-devel \
    libXxf86vm-devel mesa-libGL-devel mesa-libEGL-devel vulkan-loader-devel \
    freetype-devel fontconfig-devel gnutls-devel systemd-devel dbus-devel \
    pulseaudio-libs-devel alsa-lib-devel >/dev/null

major="${WINE_VERSION%%.*}"
cd /tmp
curl -fsSL "https://dl.winehq.org/wine/source/${major}.x/wine-${WINE_VERSION}.tar.xz" -o wine.tar.xz
tar -xJf wine.tar.xz
cd "wine-${WINE_VERSION}"
for p in $PATCHES; do
    echo "パッチ: $p"
    patch -p1 --no-backup-if-mismatch < "/patches/$p" > /dev/null
done

mkdir build && cd build
# 使わない機能は外す(印刷・スキャナー・カメラ・動画の再生・Kerberos など)。
# 残すもの: X11 と XInput2(筆圧)・XRandR、GL・EGL・Vulkan、FreeType・fontconfig、GnuTLS(https)、
# udev(TABMATE の hidraw)、D-Bus、PulseAudio・ALSA
../configure --prefix=/usr --enable-archs=i386,x86_64 --disable-tests \
    --without-wayland --without-gstreamer --without-ffmpeg --without-oss --without-pcsclite \
    --without-sane --without-gphoto --without-cups --without-capi --without-krb5 \
    --without-netapi --without-v4l2 --without-usb --without-sdl --without-unwind \
    > configure.log 2>&1 || { tail -40 configure.log; exit 1; }

for f in HAVE_X11_EXTENSIONS_XINPUT2_H HAVE_X11_EXTENSIONS_XRANDR_H HAVE_LIBXSHAPE \
         HAVE_X11_EXTENSIONS_XSHM_H SONAME_LIBXCOMPOSITE SONAME_LIBGL SONAME_LIBEGL \
         SONAME_LIBVULKAN SONAME_LIBFREETYPE SONAME_LIBFONTCONFIG SONAME_LIBGNUTLS \
         HAVE_LIBUDEV_H SONAME_LIBDBUS_1; do
    grep -q "#define $f" include/config.h || { echo "足りない機能: $f" >&2; exit 1; }
done
grep -q '^PE_ARCHS = *i386 x86_64' Makefile || { echo "PE のビルドが有効になっていません" >&2; exit 1; }

make -j"$(nproc)" > make.log 2>&1 || { grep -E 'error' make.log | tail -30; exit 1; }
make install-lib DESTDIR=/tmp/stage > install.log 2>&1 || { tail -30 install.log; exit 1; }

# Windows の DLL を、mingw の GCC で作ったものに入れ替える。抜けがあれば止める。
for arch in x86_64-windows i386-windows; do
    missing="$(cd "/tmp/stage/usr/lib/wine/$arch" && for f in *; do [[ -e "/pe/$arch/$f" ]] || echo "$f"; done)"
    if [[ -n "$missing" ]]; then
        echo "1段目に無い DLL があります($arch): $missing" >&2
        exit 1
    fi
    rm -rf "/tmp/stage/usr/lib/wine/$arch"
    cp -a "/pe/$arch" "/tmp/stage/usr/lib/wine/$arch"
done

# 置き場所を選ばない形(どこに展開しても動く)にまとめる
mv /tmp/stage/usr "/tmp/$NAME"
rm -rf "/tmp/$NAME/include" "/tmp/$NAME/share/man" "/tmp/$NAME/share/applications"
find "/tmp/$NAME/lib/wine/x86_64-unix" -name '*.so' -exec strip --strip-unneeded {} +
strip --strip-unneeded "/tmp/$NAME/bin/wine" "/tmp/$NAME/bin/wineserver" 2>/dev/null || true
cp /patches/../REVISION "/tmp/$NAME/" 2>/dev/null || true
mkdir -p "/tmp/$NAME/share/doc/clistux" "/tmp/$NAME/share/clistux"
cp -r /pe/wv2check "/tmp/$NAME/share/clistux/wv2check"
cp -r /patches "/tmp/$NAME/share/doc/clistux/patches"
cp ../LICENSE ../COPYING.LIB "/tmp/$NAME/share/doc/clistux/" 2>/dev/null || true
echo "wine-${WINE_VERSION} + clistux patches: $PATCHES" > "/tmp/$NAME/share/doc/clistux/BUILD-INFO"

cd /tmp
tar -cJf "/out/$NAME.tar.xz" "$NAME"
cp wine.tar.xz "/out/wine-${WINE_VERSION}.tar.xz"
(cd /out && sha256sum "$NAME.tar.xz" > "$NAME.tar.xz.sha256")
echo "できました: $NAME.tar.xz"
BUILD

ls -la "$DIST/$NAME.tar.xz"
cat "$DIST/$NAME.tar.xz.sha256"
