# shellcheck shell=bash
# Hyprland の設定を調べて、CSP のために足すとよい設定を案内する(clistux doctor から呼ぶ)。何も変えない。
#
# Wine の側で直せるもの(管理外の窓・余分なクリック・最大化の返事・窓の移動)は、起動スクリプトが自動で対処する。
# ここでは、利用者の設定でしか直せないものを、設定と状態を調べた結果に合わせて案内する。
# Omarchy 向けの行は、OS の名前ではなく、設定ファイルで Omarchy の o.window を使っているかで判断する。

hyprland_running() {
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl >/dev/null 2>&1 \
        && timeout 3 hyprctl version >/dev/null 2>&1
}

# 利用者の Hyprland の設定ファイルの中身(*.lua と *.conf、コメントの行は除く)
hyprland_config_text() {
    local dir="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
    [[ -d "$dir" ]] || return 0
    find "$dir" -maxdepth 2 -type f \( -name '*.lua' -o -name '*.conf' \) ! -name '*.bak*' -print0 2>/dev/null \
        | xargs -0 -r cat 2>/dev/null | grep -vE '^[[:space:]]*(--|#)'
}

hyprland_option() {
    timeout 3 hyprctl -j getoption "$1" 2>/dev/null | python3 -I -c '
import json, sys
try:
    o = json.load(sys.stdin)
except ValueError:
    sys.exit()
for k in ("int", "str", "float", "custom"):
    if k in o:
        print(o[k]); break
' 2>/dev/null
}

check_hyprland() {
    hyprland_running || return 0
    ok "デスクトップ: Hyprland(窓・クリックの対処は起動スクリプトが自動で行います)"

    local conf lua=0 omarchy=0
    conf="$(hyprland_config_text)"
    [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua" ]] && lua=1
    # Omarchy の o.window: 設定で使っているか、設定が読み込む Omarchy の補助ファイルに定義がある
    if grep -q 'o\.window(' <<< "$conf"; then
        omarchy=1
    elif grep -qi 'omarchy' <<< "$conf" \
        && grep -qs 'function o\.window' "${OMARCHY_PATH:-/usr/share/omarchy}/default/hypr/helpers.lua"; then
        omarchy=1
    fi

    # 1. Wine の窓: 移動のアニメーション(と、Omarchy の floating モードでは大きさ)。2. fcitx5 の候補の窓
    local need_exe=1 need_fcitx=0
    grep -E '\\\.exe' <<< "$conf" | grep -qE 'no_?anim' && need_exe=0
    if ((omarchy)); then
        grep -E '\\\.exe' <<< "$conf" | grep -qE 'float' || need_exe=1
        if pgrep -u "$(id -u)" -x fcitx5 >/dev/null 2>&1 && ! grep -E 'fcitx' <<< "$conf" | grep -qE 'float'; then
            need_fcitx=1
        fi
    fi
    if ((need_exe || need_fcitx)); then
        warn "Hyprland の設定に、CSP のための規則を足すことをおすすめします。"
        if ((omarchy)); then
            info "  ~/.config/hypr/hyprland.lua に次の行を足してください(Omarchy の o.window を使う設定です):"
            ((need_exe)) && info '    o.window(".*\\.exe", { float = true, no_anim = true })'
            ((need_fcitx)) && info '    o.window("fcitx.*", { float = true })'
            ((need_exe)) && info "  float: floating モードで窓が広がり、クリックの位置がずれるのを防ぎます。"
            ((need_fcitx)) && info "  fcitx.*: 日本語入力の候補の窓が、半透明の大きな窓になるのを防ぎます。"
        elif ((lua)); then
            info "  ~/.config/hypr/hyprland.lua に次の行を足してください:"
            info '    hl.window_rule({ match = { class = ".*\\.exe" }, no_anim = true })'
        else
            info "  Wine の窓(class が「〜.exe」)に no_anim の窓の規則を足してください(書き方は Hyprland の版によって違います)。"
        fi
        ((need_exe)) && info "  no_anim: CSP のタイトルバーで窓を動かすときに、窓が揺れるのを防ぎます。"
    else
        ok "Hyprland の窓の規則: 済み"
    fi

    # 3. ペン: 液晶タブレットと別のモニターがあるのに、ペンの割り当て先が決まっていない
    local tablets monitors output
    tablets=$(timeout 3 hyprctl -j devices 2>/dev/null | python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    sys.exit()
print("\n".join(sorted({t["name"] for t in d.get("tablets", []) if t.get("name")})))
' 2>/dev/null)
    monitors=$(timeout 3 hyprctl -j monitors 2>/dev/null | python3 -I -c '
import json, sys
try:
    ms = json.load(sys.stdin)
except ValueError:
    sys.exit()
for m in ms:
    print(m.get("name", "") + "\t" + m.get("description", ""))
' 2>/dev/null)
    output="$(hyprland_option input:tablet:output)"
    if [[ -n "$tablets" && $(grep -c . <<< "$monitors") -gt 1 && ( -z "$output" || "$output" == "[[EMPTY]]" ) ]]; then
        warn "ペンタブレットがあり、モニターが複数ありますが、ペンを割り当てる画面が決まっていません。"
        info "  液晶タブレットのペンは、そのままではすべての画面を合わせた範囲に割り当てられ、位置が大きくずれます。"
        info "  液晶タブレットの画面の名前を、Hyprland の設定の input の tablet の output に指定してください。"
        ((lua)) && info '    例: hl.config({ input = { tablet = { output = "DP-1" } } })'
        info "  ペン: $(tr '\n' ' ' <<< "$tablets")"
        info "  画面:"
        while IFS=$'\t' read -r n d; do [[ -n "$n" ]] && info "    $n  $d"; done <<< "$monitors"
    fi

    # 4. メニューのハイライト
    if [[ "$(hyprland_option input:follow_mouse)" == 0 ]]; then
        info "Hyprland の follow_mouse が 0 なので、CSP のメニューの項目は、マウスを乗せただけではハイライトされません(クリックすれば選べます)。"
    fi
}
