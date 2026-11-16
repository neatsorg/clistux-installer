# shellcheck shell=bash
# ほかの方法(CSPenguin、Bottles、Lutris、素の Wine など)で入れた CSP からの引き継ぎ。
#
# 引き継ぐもの: 利用者のデータ(AppData\Roaming\CELSYSUserData: ツール・ブラシ・ワークスペース・ショートカット・素材)と、
#   環境設定・ウィンドウの配置(AppData\Roaming\CELSYS の Preference・Placement など)。
# 引き継がないもの: キャッシュ・一時ファイル、認証・ライセンスに関わるもの(Certification・promenade)。
#   引き継いだ後に、もう一度ログインしてもらう。
# 作品: ふつうは「ドキュメント」が Linux の ~/ドキュメント へのリンクなので、何もしなくても見える。
#   元の環境の「ドキュメント」がふつうのフォルダー(Bottles など)なら、~/ドキュメント の下に写す。
# 元の環境は変更しない(消すのは元のツールに任せる)。

# 探す場所(プレフィックスか、プレフィックスを並べたフォルダー)
migrate_search_roots() {
    printf '%s\n' \
        "$HOME/.wine-csp" "$HOME/.wine" \
        "$HOME"/.local/share/wineprefixes/* \
        "$HOME"/.var/app/com.usebottles.bottles/data/bottles/bottles/* \
        "$HOME"/.local/share/bottles/bottles/* \
        "$HOME"/Games/* \
        "$HOME"/.PlayOnLinux/wineprefix/*
}

# プレフィックスの中で、CSP の利用者のデータを持っている利用者のフォルダーを返す
migrate_user_dir() {
    local prefix="$1" u
    for u in "$prefix"/drive_c/users/*; do
        [[ -d "$u/AppData/Roaming/CELSYSUserData" || -d "$u/AppData/Roaming/CELSYS" ]] || continue
        echo "$u"
        return 0
    done
    return 1
}

# 引き継ぎ元の候補を「プレフィックス<TAB>利用者のフォルダー」で並べる(このインストーラのプレフィックスは除く)
migrate_candidates() {
    local p u
    while read -r p; do
        [[ -d "$p/drive_c" ]] || continue
        [[ "$(readlink -f "$p")" == "$(readlink -f "$PREFIX")" ]] && continue
        u="$(migrate_user_dir "$p")" || continue
        printf '%s\t%s\n' "$p" "$u"
    done < <(migrate_search_roots)
}

# 引き継ぎ元のプレフィックスで、CSP や CLIP STUDIO が動いているか
migrate_source_busy() {
    local prefix="$1" pid
    for pid in $(pgrep -u "$(id -u)" -f 'CLIPStudio[A-Za-z]*\.exe' 2>/dev/null); do
        tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -qxF "WINEPREFIX=$prefix" && return 0
    done
    return 1
}

# 写すもの(利用者のフォルダーからの相対パス)と、除くもの
MIGRATE_ITEMS=(AppData/Roaming/CELSYSUserData AppData/Roaming/CELSYS)
MIGRATE_EXCLUDES=(
    '*/CacheData' '*/IccTemporary' '*InterProcessTemp*'
    'AppData/Roaming/CELSYS/interprocess' 'AppData/Roaming/CELSYS/Analytics'
    'AppData/Roaming/CELSYS/promenade' '*/Certification'
)

migrate_from() {
    local src_prefix="$1" src_user="$2" dst_user stamp item size_kb avail_kb ex=()
    dst_user="$PREFIX/drive_c/users/$USER"
    [[ -d "$dst_user" ]] || die "CSP 専用の環境がまだありません。先に導入してください。"
    if migrate_source_busy "$src_prefix"; then
        die "引き継ぎ元の CLIP STUDIO PAINT か CLIP STUDIO が動いています。" "保存して閉じてから、もう一度実行してください。"
    fi
    require_idle
    if [[ "$(basename "$src_user")" != "$USER" ]]; then
        warn "前の環境の利用者の名前($(basename "$src_user"))が、今の利用者($USER)と違います。"
        warn "素材の一部が見つからないことがあります。その場合は、CSP の素材の画面から読み込み直してください。"
    fi

    # 容量の確認(写す量 + 余裕 1 GB)
    for item in "${MIGRATE_EXCLUDES[@]}"; do ex+=("--exclude=$item"); done
    size_kb="$(cd "$src_user" && du -sk "${ex[@]}" -- "${MIGRATE_ITEMS[@]}" 2>/dev/null | awk '{s += $1} END {print s + 0}')"
    avail_kb="$(df -Pk "$PREFIX" | awk 'NR==2 {print $4}')"
    ((avail_kb > size_kb + 1024 * 1024)) || die "空き容量が足りません(引き継ぐデータは約 $((size_kb / 1024)) MB)。"

    # 新しい環境にすでにある設定は、上書きせずに控えに移す
    stamp="$(date +%Y%m%d-%H%M%S)"
    for item in "${MIGRATE_ITEMS[@]}"; do
        if [[ -e "$dst_user/$item" ]]; then
            mv "$dst_user/$item" "$dst_user/$item.before-migrate-$stamp"
            info "今の設定を控えに移しました: $(basename "$item").before-migrate-$stamp"
        fi
    done

    info "設定と素材を写しています(約 $((size_kb / 1024)) MB)…"
    (cd "$src_user" && tar -cf - "${ex[@]}" -- "${MIGRATE_ITEMS[@]}" 2>/dev/null) \
        | (cd "$dst_user" && tar -xf -) || die "設定と素材を写せませんでした。"
    ok "設定と素材を引き継ぎました(引き継ぎ元: $src_prefix)"

    migrate_documents "$src_user"
}

# 元の環境の「ドキュメント」がふつうのフォルダーなら、作品を ~/ドキュメント の下に写す
migrate_documents() {
    local src_docs="$1/Documents" docs dest
    docs="$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "$HOME/Documents")"
    if [[ -L "$src_docs" ]]; then
        ok "作品は「$(readlink -f "$src_docs")」にあります(前の環境の外なので、そのまま使えます)"
        return
    fi
    [[ -d "$src_docs" ]] || return 0
    if [[ -z "$(find "$src_docs" -mindepth 1 -maxdepth 3 -print -quit 2>/dev/null)" ]]; then
        return 0
    fi
    dest="$docs/前の環境のドキュメント($(date +%Y-%m-%d))"
    mkdir -p "$dest"
    cp -a "$src_docs/." "$dest/" || die "作品を写せませんでした: $src_docs"
    ok "前の環境の「ドキュメント」の中身を写しました: $dest"
}

# 引き継ぎ元を選んで引き継ぐ。ask=1 なら、見つかったときに引き継ぐかを聞く(install から)。
cmd_migrate() {
    local ask="${1:-0}" list n i choice src_prefix src_user
    if [[ -n "${OPT_FROM:-}" ]]; then
        src_prefix="$OPT_FROM"
        src_user="$(migrate_user_dir "$src_prefix")" || die "$src_prefix に CSP の設定が見つかりません。"
    else
        mapfile -t list < <(migrate_candidates)
        n=${#list[@]}
        if ((n == 0)); then
            ((ask)) || info "ほかの方法で入れた CSP は見つかりませんでした(場所を指定するには --from)。"
            return 0
        fi
        info "ほかの方法で入れた CLIP STUDIO PAINT が見つかりました:"
        for ((i = 0; i < n; i++)); do
            info "  $((i + 1)). ${list[i]%%$'\t'*}"
        done
        info "ここから、ツール・ブラシ・ワークスペース・ショートカット・素材などを引き継げます。"
        info "前の環境は変更しません。引き継いだ後に、CLIP STUDIO へのログインをもう一度お願いします。"
        [[ -t 0 ]] || { info "引き継ぐには、端末で「$(basename "$0") migrate」を実行してください。"; return 0; }
        if ((n == 1)); then
            confirm "引き継ぎますか? " || { info "引き継ぎませんでした(あとで「$(basename "$0") migrate」でできます)。"; return 0; }
            choice=1
        else
            read -r -p "  引き継ぐものの番号を入力して Enter キーを押してください(引き継がないときは 0): " choice
            [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= n)) || { info "引き継ぎませんでした。"; return 0; }
        fi
        src_prefix="${list[choice - 1]%%$'\t'*}"
        src_user="${list[choice - 1]#*$'\t'}"
    fi

    migrate_from "$src_prefix" "$src_user"
    info "前の環境($src_prefix)は、元のツールで消してかまいません。"
    info "前のツールが作ったアプリのメニューの項目が残っている場合は、元のツールの削除の手順で消してください。"
}
