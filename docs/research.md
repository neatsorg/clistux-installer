# 下調べ

仕様書(spec.md)の「要調査」を埋めるための調査メモ。
既存のインストーラ(CSPenguin、2026-11-13 時点の main)を読んで拾った事実と、作者が判断で選んだことを、項目ごとに分けて書く。

- **出典**:どこで知ったか。「CSPenguin」は、CSPenguin のインストーラで見たという意味。
- **種類**:「事実」は、誰が調べても同じになるもの(必要なランタイム、URL の形など)。
  「選択」は、正解が1つでないもの。ほかの案と比べてから採るかどうかを決める。
- **状態**:「未確認」は読んだだけ。「確認済み」は作者の環境(CachyOS、COSMIC)で確かめたもの(日付と方法を書く)。

コードや文章は写していない。設定値のように、事実そのものが短い値のものだけを書いている。

## 1. Wine 本体

| 項目 | 出典 | 種類 | 状態 | メモ |
|---|---|---|---|---|
| Wine 11.4 を使っている | CSPenguin | 選択 | 確認済み(作者の環境で動作中) | Kron4ek の配布ビルドを使用。`wine --version` は `wine-11.4` で、staging ではない(2026-11-15 に確認。以前「staging 入り」と書いたのは誤り)。Windows の DLL は mingw の GCC 12.5 でビルドされている。こちらは自前でビルドする(spec.md 2) |
| FreeType 2.13.2 を Wine のそばに置き、`LD_LIBRARY_PATH` で優先させている(64bit・32bit) | CSPenguin | 選択 | 未確認 | **理由が書かれていない**。新しい FreeType で何かが壊れるのか(文字の描画、太さ、速度)を確かめる。不要なら採らない |
| 32bit の FreeType が動くよう、32bit の zlib・bzip2・libpng・harfbuzz・brotli を入れている | CSPenguin | 事実 | 未確認 | 上の FreeType を同梱する場合だけ必要。WoW64 だけで動かせるなら 32bit 自体が要らない可能性がある(要調査) |

## 2. プレフィックスの中身

| 項目 | 出典 | 種類 | 状態 | メモ |
|---|---|---|---|---|
| 64bit のプレフィックス(win64) | CSPenguin | 事実 | 確認済み | |
| winetricks で corefonts・vcrun2022・dotnet48・dxvk・vkd3d を入れている | CSPenguin | 選択 | 未確認 | **どれが本当に要るかを1つずつ確かめる**。dotnet48 は導入に10〜30分かかるので、要らなければ大きな改善。dxvk・vkd3d は CSP の描画(OpenGL / DirectX)次第 |
| Wine Gecko 2.47.4(MSHTML)を入れている | CSPenguin | 選択 | 未確認 | 何の画面に要るのかを確かめる |
| WebView2 ランタイムを入れている(ログイン・ストアの画面用) | CSPenguin | 事実 | 未確認 | CSP の新しい版はログイン画面などに WebView2 を使う。配布元は Microsoft の固定 URL |
| `msedgewebview2.exe` は Windows 7、`CLIPStudioPaint.exe` と `CLIPStudio.exe` は Windows 8.1、全体は Windows 10 として見せている | CSPenguin | 選択 | 未確認 | 版ごとの理由を確かめる(WebView2 を win7 にすると何が回避されるのか) |
| WebView2 に `--no-sandbox` などの起動引数を環境変数で渡している | CSPenguin | 選択 | 未確認 | sandbox を切るのは Wine では一般的な回避策。最小限の引数で足りるかを確かめる |
| `concrt140` を native 優先にしている | CSPenguin | 事実 | 未確認 | vcrun2022 のものを使わせる設定。理由は要調査 |
| `dcomp.dll` を独自に作って入れている(ログイン・ストアの画面用) | CSPenguin | — | — | **使えない**(作者 en のバイナリ)。Wine 11 自身の dcomp で足りるか、足りなければ何が欠けているかを調べる |
| mfplat・mfreadwrite・winegstreamer を差し替え、動画の書き出しを可能にしている。GStreamer の h264parse を要求 | CSPenguin | — | — | **使えない**(作者 en のパッチとバイナリ)。Wine の上流でどこまで対応したかを調べ、必要なら自分でパッチを書く |
| クラッシュのダイアログを出さない(`WineDbg` の `ShowCrashDialog=0`) | CSPenguin | 選択 | 未確認 | 不具合の報告にはダイアログやログがあったほうがよい場面もある |
| PlugPlay を無効(`Start=4`)にしている | CSPenguin | 選択 | **採らない**(2026-11-13) | 無効だと機器の追加・削除の通知が届かず、CSP が後からつないだ TABMATE を拾えない。有効にしても起動の遅さは体感で変わらなかった |
| WineBus を無効(`Start=4`)にしている | CSPenguin | 選択 | 要調査 | 作者の環境では `Start=4` のままでも winebus が動いていた(TABMATE が使えている)。設定が効いていないのか、別の経路で読み込まれるのかを確かめる |
| `dxvk.conf` で、面の作成の遅延、パイプラインライブラリ、コンパイルのスレッド数などを設定 | CSPenguin | 選択 | 未確認 | DXVK を使う場合だけ意味がある |

## 3. フォント

| 項目 | 出典 | 種類 | 状態 | メモ |
|---|---|---|---|---|
| winetricks の cjkfonts(Source Han Sans、112MB・28書体)を入れると、CSP の起動が約60秒遅くなる | CSPenguin | 事実 | 未確認 | 起動のたびにフォントを走査するためと書かれている |
| 代わりに WenQuanYi Micro Hei を入れ、MS ゴシック・メイリオ・游ゴシックなど日中韓の Windows フォント名をすべてこれに置き換えている(`Fonts\Replacements`) | CSPenguin | 選択 | **日本語向けには採らない方向** | WenQuanYi は中国語のフォントなので、日本語の字形(「直」「骨」など)が中国式になる。日本語の利用者向けには、日本語の字形を持つ軽いフォントを選ぶ(候補は下) |
| フォントのアンチエイリアス(`X11 Driver` の ClientSideAntiAlias…)とフォントのキャッシュ(`Fonts` の `Cache`)を設定 | CSPenguin | 選択 | 未確認 | 効果を確かめる |

日本語フォントの候補(要調査:サイズ、起動時間への影響、ライセンス):

- Noto Sans CJK JP / Noto Sans JP(OFL)。JP 版だけなら Source Han Sans 全体よりずっと軽い
- IPAex ゴシック(IPA フォントライセンス)
- 利用者の Linux 側に入っている日本語フォントを、プレフィックスにリンクする(同梱しない案)

## 4. 起動

| 項目 | 出典 | 種類 | 状態 | メモ |
|---|---|---|---|---|
| esync・fsync を有効にし、esync のために開けるファイル数の上限を 524288 に上げている(systemd のユーザー設定と `/etc/security/limits.d`、sudo) | CSPenguin | 選択 | **採らない**(2026-11-13) | ntsync を使う。下の「ntsync の確認」 |
| `STAGING_SHARED_MEMORY`・`STAGING_WRITECOPY` などの wine-staging 用の変数 | CSPenguin | 選択 | 未確認 | staging 入りの Wine でだけ意味がある。CSPenguin の Wine も staging ではないので、効いていない |
| `DXVK_ASYNC`・`RADV_PERFTEST=gpl`・`mesa_glthread` などの描画の変数 | CSPenguin | 選択 | 未確認 | `DXVK_ASYNC` は非公式の DXVK でしか効かない。`RADV_PERFTEST=gpl` は新しい Mesa では既定。1つずつ要否を確かめる |
| 起動前に、素材のデータベース(CELSYS フォルダの `*.sqlite`・`*.db`)を読んでページキャッシュに載せている | CSPenguin | 選択 | 未確認 | 効果を測る(初回の起動、2回目の起動) |
| ログイン時に wineserver を常駐させる systemd のユーザーサービス(`Restart=always`)を、希望すれば入れる | CSPenguin | 選択 | **問題あり**(2026-11-11) | 起動の5〜10秒短縮をうたう。作者の環境では、CSP の起動のたびに wineserver が作り直され、古い winedevice.exe が取り残された。常駐を増やさない方針とも合わない |
| CSP のウィンドウが全画面になったら、wmctrl・xprop で全画面を外し続ける見張りを、起動スクリプトの中で動かしている | CSPenguin | 選択 | 未確認 | 全画面になる原因と、どのデスクトップで起きるかを確かめる。winex11 や win32u のパッチで直せるなら、見張りは要らない |
| 仮想マシンでは、Mesa のソフトウェア描画に切り替えている | CSPenguin | 事実 | 未確認 | 開発のときに役立つ |

### ntsync の確認(2026-11-13)

- カーネル 7.3.3(CachyOS)。`ntsync` はモジュール(`CONFIG_NTSYNC=m`)で、読み込み済み。`/dev/ntsync` は `crw-rw-rw-`(誰でも読み書きできる)。
- 動いている CSP(Wine 11.4、Kron4ek のビルド)で、各プロセスが `/dev/ntsync` を開いていた:
  wineserver 1340個、CLIPStudioPaint.exe 98個、services.exe 49個など。
- esync・fsync は使われていない:CSP の eventfd は3個だけで、`/dev/shm` に fsync の共有メモリも無い。
  この Wine の `ntdll.so` には esync・fsync の処理自体が入っていない(「fsync」の文字列は glibc の `fsync()` だけ)。
- **結論**:Wine 11 は `/dev/ntsync` があれば自動で ntsync を使う。`WINEESYNC`・`WINEFSYNC` の環境変数と、
  ファイル数の上限の変更は不要。
- 要調査:ほかのディストリビューションで `/dev/ntsync` の権限とモジュールの自動読み込みがどうなっているか。
  ntsync が使えないときの Wine の動作(wineserver で同期するので遅くなるはず)と、その検出方法。

## 5. CSP 本体

| 項目 | 出典 | 種類 | 状態 | メモ |
|---|---|---|---|---|
| インストーラの URL は `https://vd.clipstudio.net/clipcontent/paint/app/<版>/CSP_<版>w_setup.exe`(版は 512、504 など、ドットなし) | CSPenguin | 事実 | 未確認 | 公式の配布元から直接取る形。利用規約の確認が必要(spec.md 4) |
| 対応例として 1.13.2 から 5.1.2 まで並べている。「買い切り版」の区切りは 2.0.6・3.0.8・4.0.10・5.0.4 | CSPenguin | 事実 | 未確認 | 公式サイトの版の一覧で確かめる |
| インストール先は `C:\Program Files\CELSYS\CLIP STUDIO 1.5\` の下に `CLIP STUDIO PAINT\CLIPStudioPaint.exe` と `CLIP STUDIO\CLIPStudio.exe` | CSPenguin | 事実 | 確認済み(作者の環境のプレフィックス) | |
| インストーラは GUI で、利用者が操作する | CSPenguin | 事実 | 未確認 | サイレントインストールの可否は要調査 |
| インストーラが作る `.desktop` を消している。インストール中は `winemenubuilder.exe` を無効にしている | CSPenguin | 選択 | 未確認 | 自分の `.desktop` と二重にならないようにするため |

## 6. デスクトップとの統合

| 項目 | 出典 | 種類 | 状態 | メモ |
|---|---|---|---|---|
| ウィンドウのクラスは `clipstudiopaint.exe`・`clipstudio.exe`(`StartupWMClass` に使う) | CSPenguin | 事実 | 確認済み(xprop) | |
| `.clip` の MIME 型を `application/x-clip` として登録している | CSPenguin | 選択 | 未確認 | 公式の MIME 型は無い(要調査)。名前の付け方は自分で決めてよい |
| `.clip` のサムネイルを作るプログラムを入れている | CSPenguin | — | — | **使えない**(作者 en)。`.clip` の中のプレビュー画像の取り出し方を調べ、自分で作る |
| アイコンはリポジトリに入れず、Wikimedia Commons から取っている(商標への配慮) | CSPenguin | 選択 | 未確認 | 商標の扱いは要調査。こちらも同梱しない方針がよさそう |
| KDE では、CSP の子ウィンドウを常に手前・タスクバーに出さない、というウィンドウルールを入れている | CSPenguin | 選択 | 未確認 | KDE Plasma で何が起きるのかを確かめる |
| Huion の独自ドライバが動いていると、Wine で筆圧が効かないことがあると警告している | CSPenguin | 事実 | 未確認 | 案内に入れる候補 |
| 筆圧は CSP の「マウスモード」、高 DPI は winecfg の DPI で、と案内している | CSPenguin | 事実 | マウスモードは確認済み | |

## 7. 必要なコマンド・パッケージ

CSPenguin が確かめているもの:wget、curl、zstd、wmctrl、xprop、file、cabextract、GStreamer(h264parse を含む good と bad のプラグイン)。

- wmctrl・xprop は全画面の見張り、zstd は FreeType の展開、cabextract は winetricks、GStreamer は動画の書き出しのため。
  こちらでどれが要るかは、採る機能が決まってから決める。

## 7.5 何も足さないプレフィックスでの試験(2026-11-13)

条件:Wine 11.4(Kron4ek のビルド)、新しい 64bit のプレフィックス、winetricks なし、Wine Mono・Gecko なし
(`WINEDLLOVERRIDES=mscoree=d;mshtml=d`)、CSP 5.1.5。

- 最新版の探し方:公式の配布 URL に版番号を当てると、512・514・515 があり、513 と 516 以降は無かった。
  5.1.5 は 2026-09-15 更新、488,887,280 バイト、SHA-256 `9955e53321a59c0cea9054f7b0aa825d40fef3247e90ec1f2c2304a5f17b3251`。
  インストーラは 32bit の PE。**版の一覧を公式から正しく取る方法は要調査**(5.2 以降で番号の付け方が変わるかもしれない)。
- プレフィックスの作成は約10秒。Wine 11.4 の初期値は Windows 10 相当(CurrentVersion 6.3)、PlugPlay は `Start=2`。
- **CSP のインストーラは何も足さずに完了した**。WebView2 ランタイム(115.0.1901.200)はインストーラが自分で入れる。
  `LipPreview.dll` の登録だけ失敗した(`ClipPreview.dll` は成功)。用途は要調査。
- **起動すると、中身の無いメイン画面と、真っ白なダイアログ(タスクバーに出ない、別のウィンドウに従属)が出て止まる**。
  CSP は CPU をほとんど使わずに待ち続ける。WebView2 のブラウザのプロセス(`msedgewebview2.exe`)は一度も起動しない。
- 次の3つは、単独でも全部入れても効かなかった:WebView2 の起動引数 `--no-sandbox`、`msedgewebview2.exe` を Windows 7 扱い、
  CSP 本体を Windows 8.1 扱い・Windows 7 扱い。
- **原因は DirectComposition**:CSP は起動中に `DCompositionCreateDevice2`(`IDCompositionDesktopDevice`、
  `{5f4633fe-1e08-4cb8-8c75-ce24333f5602}`)を十数回呼び、Wine の dcomp が仮の実装なので毎回失敗している。
  Windows 7 扱いにしても呼ぶので、DirectComposition を使わない道は無いと見られる。
- Wine の上流の dcomp は、2026-10 の 11.21 の時点でも仮の実装のまま(2020 年に枠だけ作られ、その後は細かな整理だけ)。
  CSPenguin は独自の dcomp(C++ で約860行)を入れて回避している(使えない)。
- **結論**:CSP 5.x を動かすには、DirectComposition を自分で実装する必要がある。これがこのプロジェクトで一番大きな課題。

## 7.6 DirectComposition の調査(2026-11-13)

調査用の dcomp(`wine/patches/dcomp-investigation.patch`)を試験用の Wine に入れて、CSP 5.1.5 を起動した。
デバイス・ターゲット・ビジュアルは成功を返すだけで何も描かず、ほかの生成は E_NOTIMPL を返す。

- `DCompositionCreateDevice2` は1回だけ。描画に使うデバイスは `IDXGIDevice`(D3D11)、要求は `IDCompositionDesktopDevice`。
- その後、`CreateTargetForHwnd` → `CreateVisual` → `SetRoot` → すぐに両方を解放、を約30秒で23回繰り返した。
  `SetContent`・`Commit`・サーフェスの生成は一度も呼ばれない。WebView2 のブラウザも起動しないまま。
- 対応づけたウィンドウは2つ(クラス名はどちらも `742DEA58-ED6B-4402-BC11-20DFC6D08040-…` で始まる CSP 独自のもの):
  - `200A4`(2回):`WS_POPUP`、所有者あり、**`WS_EX_NOREDIRECTIONBITMAP`**(GDI の描画面を持たず、DirectComposition でしか中身を出せない)。
    白いダイアログはこれと考えられる。
  - `100B0`(21回):`WS_CHILD`、所有者なし。何度もやり直している。
- **注意(CSPenguin の利用者の報告、Reddit)**:dcomp を全プログラムに効かせると、ペンタブレットのリングで拡大・縮小したときに
  キャンバスが固まる環境があった(KDE、Nvidia 4060)。`CLIPStudio.exe` と `msedgewebview2.exe` にだけ効かせ、
  `CLIPStudioPaint.exe` には Wine 内蔵の dcomp を使わせたら直った。**CSP 本体は DirectComposition が使えると、
  キャンバスなどにも使う可能性がある。** 実装は、CSP 本体のどの機能が DirectComposition に切り替わるかに注意する。
- 同じスレッドの別の利用者の、筆圧が効くプレフィックス:Wine 11.4、DllOverrides なし、winetricks は
  fontsmooth・sourcehansans・fakechinese・fakejapanese・fakekorean・unifont・cjkfonts。dxvk・vkd3d・corefonts は入れていない。
  winetricks の `fakejapanese`(Windows の日本語フォント名を、Linux 側の日本語フォントに置き換える)はフォントの検討の候補。

### 7.6 の続き(2026-11-13)

- 22回の繰り返しの正体は、DXGI の `CreateSwapChainForComposition` の失敗(Wine 11.4 では未実装)。
  CSP は合成用のスワップチェーンを作ってビジュアルの中身にしようとし、失敗するたびにやり直していた。
- 実装(`wine/patches/0002-…`):`CreateSwapChainForComposition` は見えない補助ウィンドウにふつうのスワップチェーンを作る。
  dcomp は `Commit` のときに、ビジュアルの木にあるスワップチェーンの表示先を、ターゲットのウィンドウに切り替える
  (Wine 内部用の private data の GUID で dxgi に伝える)。
- 結果:CSP が Direct2D で描いたダイアログの土台(白)が表示されるようになった。ウィンドウを広げると、
  スワップチェーンの元の大きさの外側が黒くなる(サイズ変更への追従は未対応)。
- それでもログイン(ライセンス)画面は出ない。WebView2 のブラウザ(`msedgewebview2.exe`)が起動しない。
  - WebView2 の部品は読み込まれ、`msedgewebview2.exe` の場所を確かめに行く(7回)が、プロセスを起動しない。
    ユーザーデータのフォルダーも作られない。
  - CSP のインストーラが入れる WebView2 は 115.0.1901.200。ふだん使いのプレフィックス(CSPenguin)は 135.0.3179.85
    (Microsoft の配信サーバーの固定 URL、SHA-256 `9f4b90be849ee2fdb1260ff5236bd0faffc5b3e5b48113918ddc6ab031ebbb9e`)。
    135 に替えても変わらなかった。
  - C++ の例外は CSP 自身のもの(boost のプロセス間通信、`std::out_of_range`)だけで、WebView2 とは無関係。
  - `WKBridge.dll`(CSP の WebView2 まわり)は CompositionController を使う形跡がある(WebView2 の画面を DirectComposition の
    ビジュアルに載せる方式)。ブラウザが起動したあとは、別プロセスの描画を重ねる仕組みが要る見込み。
  - Direct2D の `DrawImage` の合成モード `0xb`(BOUNDED_SOURCE_COPY)は未対応の FIXME が出るが、ふつうの重ね描きとして
    描画はされるので、白い原因ではない。

### ふだん使いの環境(CSPenguin)との比較(2026-11-13)

ふだん使いのプレフィックスの `LoginInfo.sqlite` と、レジストリの `HKCU\Software\Celsys\CLIP STUDIO PAINT\System` の
`SettingParam` を一時的に退避して起動した(どちらも元に戻し、バックアップと一致することを確かめた)。

- どちらを退避しても、CSP は認証済みとして起動した。初回の認証画面は再現できなかった。認証の状態がどこにあるかは不明。
- ふだん使いの環境は DXVK(`dxgi.dll`・`d3d11.dll` が native)+ CSPenguin の dcomp(native)+ Wine 内蔵の d2d1。
  試験用は Wine 内蔵の dxgi・d3d11(wined3d)。
- ふだん使いの環境でも、WebView2 の部品は読み込まれるが、**ブラウザのプロセスは起動しない**。それでもヘルプから開く
  「利用プラン情報」(イラスト付きのダイアログ)は表示される。つまり、このダイアログは CSP が自分で描いている。
- 試験用で起動時に出る白いダイアログは、イラストも出ないので別の画面(初回の認証、Web ページ)と考えられる。
  dcomp の使われ方は、ウィンドウ1つにビジュアル1つ、中身は合成用のスワップチェーン1枚だけ。
- 合成用のスワップチェーンを SEQUENTIAL(バッファー1枚)に置き換えても、白いままだった。
- 次の切り分け:WebView2 だけを動かす小さな試験プログラムで、Wine 11.4 で WebView2 のブラウザが起動するかを確かめる。

### WebView2 単体試験(2026-11-14、`tests/webview2/wv2probe`)

条件:試験用の Wine 11.4(dcomp・dxgi は自作の版)と試験用のプレフィックス、WebView2 ランタイム 135.0.3179.85、
WebView2 SDK 1.0.3179.45 の `WebView2Loader.dll`、STA とメッセージループ、表示は `NavigateToString`。

- **通常の Controller(`hwnd`):最後まで成功した。**ランタイムの探索 228ms、Environment の作成完了 240ms(`hr 0`)、
  Controller の作成完了 851ms(`hr 0`)、`NavigationCompleted` 1249ms(`success 1`)。
  ユーザーデータ(`Temp\wv2probe-hwnd\EBWebView`)も作られた。Wine 11.4 でも WebView2 自体は動く。
- **CompositionController(`composition`):作成が `hr 0x80004002`(E_NOINTERFACE)で失敗した。**
  直前に WebView2 自身が `DCompositionCreateDevice2` を呼び、`IDCompositionDevice`
  (`{c37ea93a-e7aa-450d-b16f-9746cb0407f3}`)を要求していた。自作の dcomp は `IDCompositionDesktopDevice` と
  `IDCompositionDevice2` しか返さないため。**未対応箇所として確認できた最初の具体的な失敗。**
- **訂正**:これまでブラウザのプロセスを `ps` の先頭の項目で数えていたが、Wine のプロセスの引数は
  `C:\Program Files (x86)\…\msedgewebview2.exe` のように空白を含むので、常に 0 になっていた(`hwnd` の試験で、
  ブラウザが動いていたのに 0 と出た)。**「ブラウザのプロセスが起動しない」という過去の記述のうち、プロセスの数だけを
  根拠にしたもの(ふだん使いの環境での比較を含む)は無効。** 数えるときは `ps -eo args | grep -c '[m]sedgewebview2\.exe'` を使う。
- 一方、CSP の試験で `EBWebView` のユーザーデータが一度も作られていないこと(試験プログラムは作る)と、`+process` のログに
  ブラウザの起動が無いことは、別の方法で確かめた事実なので有効。**CSP は WebView2 の Environment の作成まで進んでいない**と見られる。

## 7.7 試験の残り:.NET とフォント(2026-11-15)

### .NET(dotnet48)と Wine Mono・Gecko

- CSP と CLIP STUDIO のフォルダーにある PE ファイル 451 個を調べ、CLR のヘッダー(.NET のプログラム)を持つものは 0 個だった。
- これまでの試験はすべて `mscoree=d`(.NET を無効)と `mshtml=d`(IE エンジンを無効)で行い、メイン画面・描画・CLIP STUDIO の Web 画面・
  素材のダウンロード・ライセンスの画面まで動いた。
- **結論:dotnet48 も Wine Mono も不要。Wine Gecko も不要**(`WKBridge.dll` には WebView2 が使えないときの IE の予備があるが、
  WebView2 が動くので使われない)。

### 日本語フォント

- 作者の環境には Windows の日本語フォント(メイリオ、游ゴシック、MS ゴシック、BIZ UD など)が `~/.local/share/fonts` にあり、
  CSP はそれを使っている。ふつうの利用者には無い。
- **Windows の日本語フォントが無い状態では、CSP のメニュー・パネルの日本語がすべて豆腐(□)になった**(撮影で確認)。
  Wine はメイリオなどの代わりに Tahoma などを選び、日本語の文字を補えていなかった。**日本語フォントの設定は必須。**
- fontconfig の標準の設定では、日本語を指定しても Noto Sans CJK **KR** が選ばれた(このディストリビューションの設定)。
  Noto CJK は1つのファイルに日中韓が入っているので、**書体名に JP を明示する**必要がある。
- Wine の `HKCU\Software\Wine\Fonts\Replacements` は、**元のフォントが無いときだけ**置き換える(`win32u/font.c` の
  `load_gdi_font_replacements`:「If the font already exists the replacement does not take place.」)。
  値が `REG_MULTI_SZ` なら、並べた候補のうち最初に見つかったものを使う。
  → Windows のフォントを持つ人には影響せず、持たない人だけ補える。インストーラで常に入れてよい。
  作者の環境で入れても、画面は本物のフォントのまま変わらなかった(期待どおり)。
- Wine は fontconfig から**フォルダーの一覧**だけを受け取り、中のファイルは自分で走査する(`FcConfigGetFontDirs`)。
  さらに、見つけたフォントのパスをレジストリ(`HKLM\…\CurrentVersion\Fonts`、`HKCU\Software\Wine\Fonts\External Fonts`)に
  記録し、次回からそこからも読む。フォントを「隠す」試験では、これらにも注意が要る。
- **未確認**:Windows の日本語フォントが無い環境で、置き換えにより正しい字形で表示されること。フォントを隠す試験は、
  途中から CSP の起動が DirectWrite の中で固まった(原因不明。キャッシュの無い状態での大量のフォントの読み込みか、
  レジストリの不整合と推測)。Windows のフォントを入れていない別の PC で確かめる。

### winetricks の cjkfonts の測定(2026-11-15)

- `cjkfonts` は、プレフィックスの `Fonts` に Source Han Sans(`sourcehansans.ttc`、117MB、28書体)と unifont(12MB)を入れ、
  `Fonts\Replacements` に置き換えを入れる。
- 日本語の名前(MS ゴシック、MS UI Gothic、メイリオ、Meiryo UI、游ゴシック、Yu Gothic UI、MS 明朝、游明朝 など)は
  「Source Han Sans」(地域の指定なし=日本語の字形)へ。中国語の名前は SC/TC、韓国語は K へ。**字形の対応は正しい。**
  明朝体の名前もゴシック体(Source Han Sans)に置き換わる。
- **起動時間(3回ずつ、メインのウィンドウが出るまで / CPU が落ち着くまで)**:入れる前 3.1〜3.4 秒 / 約 10.5 秒、
  入れたあと **12.1 秒 / 19.4 秒**。毎回約 9 秒遅くなる(初回だけではない)。CSPenguin のコメントの「約 60 秒」ほどではないが、
  ウィンドウが出るまでは約 4 倍。作者の環境では本物の Windows フォントが優先されるので、この 117MB は使われてもいない。
- 測定のあと、`cjkfonts` を取り除いて元に戻した(起動 3.1 秒 / 9.5 秒に戻った)。
- **結論**:`cjkfonts` は採らない。Linux 側の日本語フォントへの置き換え(spec.md 4.7)を基本にし、日本語フォントが見つからないときだけ、
  日本語だけの軽いフォントをプレフィックスに入れる案を検討する。

## 8. 自分たちで確かめたこと(CSPenguin 以外)

| 項目 | 状態 | 詳細 |
|---|---|---|
| COSMIC でメニュー・ツールチップの位置がずれる、最大化がおかしい → winex11・win32u のパッチと作業領域ヘルパーで解決 | 確認済み(2026-11) | 作者の PR #127 と調査メモ |
| 日本語入力は `XMODIFIERS` で fcitx5 につながる。COSMIC ではログインの環境変数に書く | 確認済み(2026-11) | |
| TABMATE:winebus の hidraw 化、udev ルール、PlugPlay の有効化 | 確認済み(2026-11-12〜13) | 作者の調査メモ |
| ペンは「マウスモード」なら、ペンタブレットのモニタの位置に関係なくずれない | 確認済み(2026-11-10) | |

## 次に確かめる順番(案)

効果が大きく、確かめやすいものから。

1. ~~ntsync が使えるか~~ → 使える。確認済み(2026-11-13)
2. winetricks の各パッケージの要否、とくに dotnet48(導入時間が大きく変わる)
3. 日本語フォント(字形の正しさと起動時間)
4. FreeType を同梱する理由
5. ログイン画面と dcomp、動画の書き出し(使えないものの代わり)

## 7.8 自前でビルドした Wine で CSP が起動時に落ちた(2026-11-15)

- 条件:`wine/build.sh` で公式の 11.4 のソースから Wine 全体をビルド(Windows の DLL は clang 22 と lld)。新しいプレフィックスに CSP 5.1.5 を入れて起動。
- **観測**:起動中に落ちる。`ucrtbase.dll` の `__CxxUnregisterExceptionObject` → `_FindAndUnlinkFrame`(`dlls/msvcrt/except.c`)で、
  例外の記録の一覧に自分の分が見つからないまま末尾を越えて NULL を読む(C++ の例外を処理し終えた後の後始末)。
- CSP は C のランタイムの DLL を同梱しているが、`ucrtbase`・`vcruntime140`・`vcruntime140_1`・`msvcp140`・`concrt140` は Wine 内蔵のものが使われる
  (Kron4ek のビルドでも同じ)。
- **切り分け**:この5つを Kron4ek のビルド(同じ 11.4、staging ではない、mingw の GCC 12.5)のものに入れ替えると、落ちずに起動した。
  ソースは同じなので、**コンパイラの違い(clang 22 と GCC 12.5)が原因**。clang のどこが違うかは未調査(上流に報告する価値がある)。
- **対処**:Windows の DLL を mingw-w64 の GCC でビルドする(`wine/build.sh` の1段目、Debian 12 の GCC 12)。

## 7.9 白いお知らせの画面と WebView2 の版(2026-11-15)

- **お知らせがメイン画面の後ろに出る**:CSP のダイアログの持ち主は、1×1 の枠なしのポップアップ(それ自体も所有されている)。
  COSMIC 向けのパッチ(所有者のある枠なしのポップアップを管理外にする)により、このウィンドウは管理外のまま残り、
  ダイアログの `WM_TRANSIENT_FOR` が管理外のウィンドウを指していた。COSMIC はダイアログを手前に出さない。
  → `winex11-transient-for-managed-owner.patch`:持ち主が管理外なら、持ち主の持ち主をたどり、管理されているウィンドウを従属先にする。
  確認:環境設定と、ヘルプから開く WebView2 の画面が、すべてメイン画面に従属し、手前に出た。
- **WebView2 115 では、ブラウザのプロセスが起動中に止まる**(`EXCEPTION_BREAKPOINT`、2回起動し直して諦める)。
  CSP 5.1.5 のインストーラが入れるのは 115.0.1901.200。**135.0.3179.85 に替えると、CLIP STUDIO のホームも、CSP の中の画面
  (ヘルプの「新機能・リリースノート」)も表示された。** 以前 CSP の中の画面が 135 でも白かった(7.6)のとは結果が違う。
  違いは Wine(自前のビルド、Windows の DLL は GCC)と、上の従属先の修正。どれが効いたかは未確認。
  → インストーラで、動作を確かめた版の WebView2 を入れる必要がある(入れ方は検討中)。

## 7.10 引き継ぎと TABMATE の割り当て(2026-11-16)

- CSP の利用者のデータは `AppData\Roaming\CELSYSUserData\CELSYS`(5.1 系は `CLIPStudioPaintVer1_5_0`)。レジストリには CSP の設定は無い。
- CLIP STUDIO TABMATE の割り当ては `CLIPStudioPaintVer1_5_0\JoyPad\WTabMateSettings`(SQLite)。表 `working` の各行がボタンの割り当て
  (`B1Data`〜、中身は UTF-16 の識別子の並び)、表 `general` の `uselatestdefaultsettings` は「最新の初期値を使う」かどうか。
  機器ごとの識別子では結びついていない(`deviceid` は共通の 100)ので、別の PC や別の Wine に写しても使える。
- CSP は設定を終了時に保存する(閉じたときに `WTabMateSettings` が書き換わる)。
- 注意:作者の環境では、11 月 11 日の TABMATE の調査のときに控えたファイル(`WTabMateSettings.bak-20261111`)とは別の、試験中に
  CSP が作り直したファイルが使われ続けていた。引き継ぎの試験で割り当てが「初期値」に見えたのはこのためで、引き継ぎの不具合ではなかった。
  調査で設定のファイルを差し替えたときは、元に戻したことを確かめる。

## 7.11 ペンでタイトルバーを押すとウィンドウをつかんだままになる(COSMIC、2026-11-17)

- Wine はタイトルバーが押されると、すぐに `_NET_WM_MOVERESIZE` でウィンドウマネージャに移動を頼み、ボタンが離されるまで待つ
  (`winex11.drv/mouse.c` の `move_resize_window`)。COSMIC は、ペンで頼まれた移動を、ペンを離しても解除しない
  (マウスのボタンが離されるまで続く)。Wine の側ではペンを離したことがわかる(`ButtonRelease` が届く)。
- 試したこと:
  - 離したときに `_NET_WM_MOVERESIZE_CANCEL` を送る → COSMIC は解除しない(対応していないと見られる)
  - Wine 自身がウィンドウを動かす(XMoveWindow)→ COSMIC は、アプリによる位置の変更を受け付けない
  - Super キーを押しながらペンでドラッグ(COSMIC 自身の移動)→ これも解除されない
  - **Esc キーで解除できる**(README に回避策として書いた)
- 対処(`winex11-moveresize-drag-threshold.patch`):Windows と同じく、ドラッグの距離(SM_CXDRAG/SM_CYDRAG)を超えてから移動を頼む。
  1回のクリックやダブルクリックの1回目では移動が始まらないので、タイトルバーのダブルクリック(最大化)がアプリに届く。
- ほかのコンポジター(mutter・KWin)でも、ペンと XWayland の窓の移動の不具合が報告されている。COSMIC への報告は未。

## 7.12 Hyprland(Omarchy)で試した結果(2026-11-20)

条件: Omarchy(Hyprland 0.56、dwindle)、Intel Iris Xe、v0.1.1、Wine csp5。導入の手順はすべて成功した(ntsync が無い警告だけ)。
WebView2 は 158 が入った(wv2check は通った)。

- **窓が広がり、クリックがずれる**: Omarchy の floating モードが、Wine の窓(CSP のインストーラ、CLIP STUDIO のダイアログなど)を
  既定の大きさ(最大 1100×760)に広げる。中身は元の大きさで描かれ、余白が黒や白になり、クリックの位置もずれる。
  Hyprland の設定に `o.window(".*\\.exe", { float = true })` を足すと、窓の大きさは直る(Omarchy は float を自前で指定した窓の大きさを決めない)。
- **入力を受け付けるダイアログが押せない**: COSMIC 向けのパッチ(所有者のある枠なしの窓を管理外にする)が、CLIP STUDIO のプライバシー設定の
  ダイアログ(486×690、WM_HINTS の input は False)まで override-redirect にする。COSMIC ではクリックが届くが、Hyprland では届かない。
- **パッチを効かせないと、メニューが普通の窓になる**: 環境変数 CSPENGUIN_MANAGED_POPUPS=1 で無効にすると、ダイアログは押せるが、
  CSP の「ファイル」メニューやサブメニューが、タイトルバー付きの浮いた窓として表示される。CS では、メニューが1回目しか出ない。
- **パッチを効かせた CSP**: メニューが開かず、ペンで操作すると窓がワークスペース 42 に移った(X11 では 800×600 で (0,0))。
- **WebView2 158 か 157 か**: 157 に戻しても、上の問題は同じ。158 の問題かどうかは未確認(窓の問題に隠れて切り分けられていない)。
- 次にすること: パッチで、メニュー・ツールチップ(管理外)と入力を受け付けるダイアログ(管理下)を見分ける(候補: WS_EX_TOOLWINDOW や
  WS_EX_TOPMOST の有無、表示のときに活性化されるか)。そのうえで Hyprland の窓の扱いを1つずつ確かめる。
- 起動の記録の1行目に、Xlib の既定のエラー(`BadRROutput`、RRGetOutputInfo)があった。最初の起動のときのもので、どのプロセスかは未確認。

