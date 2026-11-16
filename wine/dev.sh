#!/usr/bin/env bash
# 開発用: Wine のソースを手元に置き、変更した DLL だけを差分ビルドして、試験用の Wine に入れる。
# 配布用のビルド(再現できるコンテナでのビルド)は別に用意する。
#
# 使い方:
#   wine/dev.sh setup            Wine のソースを取得して configure する(初回だけ)
#   wine/dev.sh build [DLL...]   DLL をビルドする(既定: dcomp)
#   wine/dev.sh install [DLL...] ビルドした DLL を試験用の Wine に入れる(既定: dcomp)
#   wine/dev.sh run [WINEDEBUG]  試験用のプレフィックスで CSP を起動する
#
# 置き場所(環境変数で変えられる):
#   CLISTUX_CACHE  ソースとビルドの置き場所(既定: ~/.cache/clistux)
#   CLISTUX_TEST   試験用の Wine とプレフィックスの置き場所(既定: ~/.local/share/clistux-test)
set -euo pipefail

WINE_VERSION="${WINE_VERSION:-11.4}"
CACHE="${CLISTUX_CACHE:-$HOME/.cache/clistux}"
TEST="${CLISTUX_TEST:-$HOME/.local/share/clistux-test}"
SRC="$CACHE/wine-src"
BUILD="$CACHE/wine-build"
TEST_WINE="$TEST/wine-$WINE_VERSION"
CSP_EXE='C:\Program Files\CELSYS\CLIP STUDIO 1.5\CLIP STUDIO PAINT\CLIPStudioPaint.exe'

die() { echo "エラー: $*" >&2; exit 1; }

cmd_setup() {
    if [[ ! -d "$SRC/.git" ]]; then
        git clone --depth 1 --branch "wine-$WINE_VERSION" https://github.com/wine-mirror/wine.git "$SRC"
        git -C "$SRC" switch -c csp-dcomp
    fi
    mkdir -p "$BUILD"
    # PE 側(Windows の DLL)は clang と lld でビルドする。mingw は要らない。
    # ここでは PE の DLL だけを作るので、Unix 側のライブラリはほとんど無効にしてよい。
    (cd "$BUILD" && "$SRC/configure" --enable-win64 --disable-tests \
        --without-x --without-freetype --without-wayland --without-gstreamer \
        --without-oss --without-alsa --without-pulse --without-pcsclite --without-sane \
        --without-gphoto --without-cups --without-capi --without-krb5 --without-netapi \
        --without-vulkan --without-opengl --without-dbus --without-gnutls --without-usb \
        --without-v4l2 --without-udev --without-sdl --without-unwind --without-ffmpeg \
        > configure.log 2>&1) || { tail -30 "$BUILD/configure.log"; die "configure に失敗しました"; }
    grep -q '^PE_ARCHS = *x86_64' "$BUILD/Makefile" || die "PE のビルドが有効になっていません($BUILD/configure.log を見てください)"
    echo "準備できました: $SRC → $BUILD"
}

dlls() { [[ $# -gt 0 ]] && printf '%s\n' "$@" || echo dcomp; }

cmd_build() {
    local targets=()
    while read -r d; do targets+=("dlls/$d/x86_64-windows/$d.dll"); done < <(dlls "$@")
    make -C "$BUILD" -j"$(nproc)" "${targets[@]}" > "$BUILD/make.log" 2>&1 \
        || { grep -E 'error|warning' "$BUILD/make.log" | tail -30; die "ビルドに失敗しました($BUILD/make.log)"; }
    printf 'ビルドしました: %s\n' "${targets[@]}"
}

cmd_install() {
    [[ -d "$TEST_WINE" ]] || die "試験用の Wine がありません: $TEST_WINE"
    local names=() d
    mapfile -t names < <(dlls "$@")
    # 先に更新元がすべてあることを確かめる(途中で失敗して、古い DLL と新しい DLL が混ざらないように)
    for d in "${names[@]}"; do
        [[ -f "$BUILD/dlls/$d/x86_64-windows/$d.dll" ]] || die "ビルドされていません: $d.dll(先に build を実行してください)"
    done
    # 実行中の試験用の Wine が、更新途中の DLL を読み込まないよう、先に止めて終了を待つ。
    # 止めるのは試験用のプレフィックスの wineserver だけ(ふだん使いのプレフィックスやサービスには触れない)。
    WINEPREFIX="$TEST/prefix" WINEDEBUG=-all "$TEST_WINE/bin/wineserver" -k 2>/dev/null || true
    WINEPREFIX="$TEST/prefix" WINEDEBUG=-all "$TEST_WINE/bin/wineserver" -w 2>/dev/null || true
    for d in "${names[@]}"; do
        install -m 755 "$BUILD/dlls/$d/x86_64-windows/$d.dll" "$TEST_WINE/lib/wine/x86_64-windows/$d.dll"
        echo "入れました: $d.dll → $TEST_WINE"
        # プレフィックスの system32 には、作成時の実物のコピーがある。WinRT のクラスのように
        # フルパス(レジストリの DllPath)で読み込まれる DLL は、こちらが使われるので一緒に更新する。
        if [[ -f "$TEST/prefix/drive_c/windows/system32/$d.dll" ]]; then
            install -m 644 "$BUILD/dlls/$d/x86_64-windows/$d.dll" "$TEST/prefix/drive_c/windows/system32/$d.dll"
            echo "入れました: $d.dll → プレフィックスの system32"
        fi
    done
}

cmd_run() {
    local debug="${1:-err+all,fixme-all,+dcomp}"
    export WINEPREFIX="$TEST/prefix" WINESERVER="$TEST_WINE/bin/wineserver"
    export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d"
    export WINEDEBUG="$debug"
    local log="$TEST/run-$(date +%Y%m%d-%H%M%S).log"
    echo "ログ: $log"
    "$TEST_WINE/bin/wine" "$CSP_EXE" > "$log" 2>&1
}

case "${1:-}" in
    setup)   shift; cmd_setup "$@" ;;
    build)   shift; cmd_build "$@" ;;
    install) shift; cmd_install "$@" ;;
    run)     shift; cmd_run "$@" ;;
    *) sed -n '2,15p' "$0"; exit 1 ;;
esac
