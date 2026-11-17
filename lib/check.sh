# shellcheck shell=bash
# 前提の確認。足りないものは、そのディストリビューションの導入コマンドの形で示す(自動では入れない)。

# ディストリビューションの系統: arch / debian / fedora / suse / other
distro_family() {
    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        id="$(. /etc/os-release; echo "${ID:-}")"
        like="$(. /etc/os-release; echo "${ID_LIKE:-}")"
    fi
    case " $id $like " in
        *" arch "*) echo arch ;;
        *" debian "*|*" ubuntu "*) echo debian ;;
        *" fedora "*|*" rhel "*) echo fedora ;;
        *" suse "*|*" opensuse "*) echo suse ;;
        *) echo other ;;
    esac
}

# 部品の名前 → 系統ごとのパッケージ名
package_name() {
    local fam="$1" what="$2"
    case "$fam:$what" in
        arch:python) echo python ;;
        *:python) echo python3 ;;
        arch:xprop) echo xorg-xprop ;;
        debian:xprop) echo x11-utils ;;
        *:xprop) echo xprop ;;
        *:fontconfig) echo fontconfig ;;
        *:cabextract) echo cabextract ;;
        arch:font-jp) echo noto-fonts-cjk ;;
        debian:font-jp) echo fonts-noto-cjk ;;
        fedora:font-jp) echo google-noto-sans-cjk-fonts google-noto-serif-cjk-fonts ;;
        suse:font-jp) echo noto-sans-cjk-fonts noto-serif-cjk-fonts ;;
        *:font-jp) echo "Noto Sans CJK JP のフォント" ;;
        *) echo "$what" ;;
    esac
}

install_hint() {
    local fam="$1"; shift
    local pkgs=() w
    for w in "$@"; do pkgs+=($(package_name "$fam" "$w")); done
    case "$fam" in
        arch)   echo "sudo pacman -S --needed ${pkgs[*]}" ;;
        debian) echo "sudo apt install ${pkgs[*]}" ;;
        fedora) echo "sudo dnf install ${pkgs[*]}" ;;
        suse)   echo "sudo zypper install ${pkgs[*]}" ;;
        *)      echo "次のものを入れてください: ${pkgs[*]}" ;;
    esac
}

# 必須の確認。問題があれば終わる。
check_requirements() {
    local fam missing=()
    fam="$(distro_family)"

    [[ "$(uname -m)" == x86_64 ]] || die "この PC の CPU($(uname -m))には対応していません。" "x86_64(一般的な Intel・AMD の 64bit CPU)が必要です。"
    [[ $EUID -ne 0 ]] || die "root(管理者)のままでは実行できません。" "sudo を付けずに、ふだんの利用者で実行してください。必要なときだけ、こちらから確認します。"
    [[ -n "${DISPLAY:-}" ]] || die "画面(X11 / XWayland)が見つかりません。" "デスクトップにログインした状態で、端末から実行してください。"

    command -v python3 >/dev/null || missing+=(python)
    command -v fc-list >/dev/null || missing+=(fontconfig)
    command -v cabextract >/dev/null || missing+=(cabextract)
    if [[ "${XDG_CURRENT_DESKTOP:-}" == *COSMIC* ]] && ! command -v xprop >/dev/null; then
        missing+=(xprop)
    fi
    for c in tar xz sha256sum curl iconv; do
        command -v "$c" >/dev/null || die "基本のコマンド「$c」がありません。" "ディストリビューションの基本パッケージを入れてください。"
    done
    if ((${#missing[@]})); then
        fail "足りないものがあります: ${missing[*]}"
        info "端末で次のコマンドを実行してから、もう一度このインストーラを実行してください:"
        info "  $(install_hint "$fam" "${missing[@]}")"
        die "必要なものが足りません。"
    fi
    ok "必要なコマンドがそろっています"

    local avail_kb
    mkdir -p "$CLISTUX_DATA"
    avail_kb="$(df -Pk "$CLISTUX_DATA" | awk 'NR==2 {print $4}')"
    if ((avail_kb < 8 * 1024 * 1024)); then
        die "空き容量が足りません(残り $((avail_kb / 1024 / 1024)) GB)。" "$CLISTUX_DATA のあるディスクに、8 GB 以上の空きが必要です。"
    fi
    ok "空き容量: $((avail_kb / 1024 / 1024)) GB"

    check_ntsync
    check_session
}

# ntsync: あれば Wine が自動で使う(速くなる)。無くても動く。
check_ntsync() {
    if [[ -r /dev/ntsync && -w /dev/ntsync ]]; then
        ok "ntsync が使えます(動作が軽くなります)"
    elif [[ -e /dev/ntsync ]]; then
        warn "ntsync はありますが、読み書きできません。動きますが、少し重くなることがあります。"
    else
        warn "ntsync がありません(Linux 6.14 以降の機能)。動きますが、少し重くなることがあります。"
        info "  入れるには: sudo modprobe ntsync(使えないときは、カーネルを新しくしてください)"
    fi
}

check_session() {
    local desk="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-${DESKTOP_SESSION:-}}}" type="${XDG_SESSION_TYPE:-}"
    # sway など、セッションの種類を設定しないデスクトップもある。画面の接続先から判断する
    [[ -z "$desk" && -n "${SWAYSOCK:-}" ]] && desk=sway
    if [[ "$type" != x11 && "$type" != wayland ]]; then
        if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then type=wayland
        elif [[ -n "${DISPLAY:-}" ]]; then type=x11
        fi
    fi
    desk="${desk:-不明}"; type="${type:-不明}"
    ok "デスクトップ: $desk($type)"
    [[ "$type" == x11 || "$type" == wayland ]] || warn "デスクトップの種類がわかりませんでした。続けますが、うまく動かないことがあります。"
}
