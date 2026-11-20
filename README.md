# Clistux Installer

**CLIP STUDIO PAINT(クリスタ)を今日的な Linux 環境で使えるようにするインストーラです。**

Windows 版の CLIP STUDIO および CLIP STUDIO PAINT を、Wine(Windows のソフトを Linux で動かす仕組み)上で動かすための準備を、まとめて行います。
日本語入力、ペンタブレットの筆圧、CLIP STUDIO TABMATE も、そのまま使えるようにします。
Linux での操作に慣れていない人でも、なるべく手軽に導入できるようにしました。
開発に AI を利用しています。画像データの学習や生成などには使っていませんが、懸念される方は使用をお控えください。
なお、このツール自体が、動作中に AI を使うことはありません。

> **ご注意**
> - これは有志による非公式のツールです。CLIP STUDIO PAINT の開発元(株式会社セルシス)とは関係がありません。
>   このツールで動かした CLIP STUDIO PAINT について、セルシスに問い合わせないでください。
> - CLIP STUDIO PAINT 本体は含まれていません。公式サイトから入手し、ライセンスはご自身でセルシスと結んでください。
> - Linux での動作は、セルシスの動作保証の対象外です。正常に動かない場合もありえますし、大切な作品は、こまめにバックアップしてください。

## できること

- CLIP STUDIO PAINT と CLIP STUDIO を、アプリのメニューから起動できるようにする
- `.clip` ファイルを、ダブルクリックで CLIP STUDIO PAINT で開けるようにする
- 日本語入力(fcitx5・IBus)、ペンタブレットの筆圧、CLIP STUDIO TABMATE を使えるようにする
- CLIP STUDIO 内の Web の画面(お知らせ・素材のダウンロード・ログイン)を表示・操作できる。素材のダウンロードなども可能
- ほかの方法(CSPenguin・Bottles など)で入れていた CLIP STUDIO PAINT があるなら、設定・素材・TABMATE の割り当てを引き継ぐ
- CLIP STUDIO PAINT を新しい版にする、うまく動かないときに診断する、削除する

## 動作環境

| 項目 | 内容 |
|---|---|
| PC | 一般的な Intel・AMD の 64bit の PC(x86_64) |
| Linux | 主なディストリビューションで動くことを目指しています(確認済み: CachyOS) |
| デスクトップ | COSMIC・KDE Plasma・GNOME など(Wayland でも X11 でも動きます)。Hyprland(Omarchy など)は、設定を少し足せば動きます(下記) |
| CLIP STUDIO PAINT | Windows 版 5.1.5 で動作を確かめています(ほかの版でも動くことが多いですが、「未確認の版」と表示されます) |
| 空き容量 | 8 GB 以上 |

## はじめての導入

### 1. CLIP STUDIO PAINT のインストーラを入手する

ブラウザで [CLIP STUDIO PAINT の公式サイト](https://www.clipstudio.net/ja/dl/) を開き、**Windows 版** をダウンロードしてください。
ファイル名は `CSP_515w_setup.exe` のような形です。標準の「ダウンロード」フォルダに保存されていれば、以下の操作を行った際に、このツールが自動で見つけます。

ダウンロードしたファイルを、ダブルクリックで開かないでください(このツールを介さない動作をするため、正しくインストールできません)。

### 2. 端末に1行貼り付けて、Enter キーを押す

「端末」(ターミナル)を開いて、次の1行を貼り付け、Enter キーを押してください。

```sh
curl -fsSL https://github.com/neatsorg/clistux-installer/releases/latest/download/install.sh | bash
```

このあとは、画面の指示に従って進めてください。途中で CLIP STUDIO PAINT のインストーラ画面が開きます。そちらも画面に従って操作してください。全体で 5〜15 分ほどかかります。

- 足りないもの(`python3`・`fontconfig`・`cabextract` など)があるときは、入れるためのコマンドが表示されます。
  それを実行してから、もう一度上記の1行を実行してください。
- もし、上記の1行で実行するのが不安なひとは、[リリースのページ](https://github.com/neatsorg/clistux-installer/releases/latest) から
  `clistux.tar.gz` をダウンロードして展開し、中の `./clistux` を実行しても同様です。

### 3. 起動する

アプリのメニューに「CLIP STUDIO PAINT」と「CLIP STUDIO」が増えます。そちらから起動してください。はじめての起動では、CLIP STUDIO へのログインや登録を求められます。そちらは Windows 版と同様の作業です。わからない方は公式サイトなどを参照してください。

- **ペンの位置がずれるとき**は、CLIP STUDIO PAINT の「ファイル」→「環境設定」→「タブレット」で「マウスモード」を選ぶと、ずれなくなる可能性が高いです。
- 初回起動時に表示される筆圧調整の画面も、マウスモードでないと、描画位置がずれてうまく描けないときがあります。その場合は筆圧調整をスキップし、先にマウスモードへの変更を行ってください。「ファイル」→「筆圧検知レベルの調節」から筆圧調整をやり直せます。

## メンテナンスが必要なときは

このツールが導入されていると、端末で `clistux` と入力するだけで、次のメニューが出ます。番号を選ぶと、それぞれの機能を使うことができます。

```text
  1. CLIP STUDIO PAINT を新しい版にする
  2. うまく動かないときの診断と修復
  3. このツールと部品(Wine・WebView2)を新しくする
  4. CLIP STUDIO TABMATE を使えるようにする
  5. ほかの方法で入れた CSP から、設定・素材を引き継ぐ
  6. 削除する
```

### CLIP STUDIO PAINT を新しい版にする

このツールはバージョンアップにできるだけ対応させたいと考えていますが、うまく動かない可能性もあります。更新は慎重に行ってください。以下が手順です。

1. 公式サイトから、バージョンアップ版の **Windows 版** のインストーラをダウンロードする
2. CLIP STUDIO PAINT と CLIP STUDIO を完全に閉じる
3. 端末で `clistux` と入力し、「1」を選ぶ

設定や素材、作品はそのまま残り、引き継ぐことができます。

### CLIP STUDIO TABMATE を使う

端末で `clistux` と入力し、「4」を選んでください(OS の管理者パスワードを聞かれます)。
TABMATE のペアリングは、デスクトップの Bluetooth の設定から行ってください。
ボタンの割り当ては、CLIP STUDIO PAINT の「ファイル」→「CLIP STUDIO TABMATE」で変えられます。なお作者は TABMATE 2 での動作を確認していません。

TABMATE は 10 分操作しないとスリープ状態になります。CLIP STUDIO ボタン以外のボタンを押すと、また接続します。スリープ状態から無操作のままさらに10分経過すると TABMATE の電源が落ち、Bluetooth から切断されます。

### ほかの方法(CSPenguin・Bottles など)で入れた環境から移行する

インストールの途中で、ほかの方法で入れた CLIP STUDIO PAINT が見つかると、引き継ぐかを聞かれます。そこで引き継がなかった場合も、あとで端末コマンド `clistux` →「5」を実行することで引き継げます。

- 引き継げるもの: ツール・ブラシ・ワークスペース・ショートカット・導入済みの素材・TABMATE のボタン割り当てなど
- 作品(拡張子 `.clip` のファイルなど)は、ふつうは Linux の「ドキュメント」フォルダに保存されているため、明示的に引き継ぐ必要がなく、そのまま開くことができます
- 引き継いだ後には、CLIP STUDIO へのログインをもう一度お願いします
- 引き継ぎの際に、前の環境は変更しません。引き継ぎが済み、もし不要になった場合は以前に使っていたツールの手順で消してかまいません

## うまく動かないとき

- 起動に失敗すると、画面の右上などに通知が出ます。
- 端末で `clistux` →「2」を選ぶと、よくある原因を調べて表示します(`clistux doctor` でも同じです)。
- 記録は `~/.local/state/clistux/` にあります。作者に問い合わせるときは、この中の `launch.log` を添えてください。なお、これはこのツールの記録ですので、内容は株式会社セルシスや CLIP STUDIO PAINT とは関係がありません。そちらに問い合わせしないでください。
- 作者はこのツールを Linux 7.3.4-1-cachyos、COSMIC-DE(cosmic-comp 1.11)(いずれも開発時点の最新)、Intel i9-10900K、GeForce RTX 2070 SUPER、96 GB RAM、Wacom Cintiq 16、CLIP STUDIO TABMATE(初代、CES-50006)という環境で検証しました。当然ながらほかの環境については把握していません。動かない場合は皆さん自身での修正を歓迎します。PR などは特に想定していませんが、有益そうならマージします。

よくある質問:

- **Web の画面(CLIP STUDIO のメイン画面、初回起動時のイントロダクション等)が真っ白で、何も表示されない**: `clistux` →「3」で、このツールで使う部品を更新してください。
- **日本語が入力できない**: fcitx5 か IBus が動いているかを確かめてください。動いていれば、CLIP STUDIO PAINT の起動時に自動で連携されます。
- **ペンでタイトルバーを動かしたあと、ウィンドウをつかんだままになる**: Esc キーを押して解除してください(COSMIC で起きることがあります)。
- **COSMIC で、起動時に画面が画面の外にはみ出す**: 現バージョンのCOSMIC は、フローティングウィンドウの表示位置を調整できません(CLIP STUDIO PAINT に限らない、COSMIC 自体の仕様です)。どうしてもはみ出さないようにしたい場合は拙作の [cosmic-geometry](https://github.com/neatsorg/cosmic-geometry) が役に立つことがあります。
- **Hyprland(Omarchy など)で使う**: ツールチップ・メニュー・ダイアログ・ペンは動きますが、次の設定と使い方が必要です。
  - Omarchy の floating モードでは、窓が余計に広がって中身とずれ、クリックの位置もずれます。
    Hyprland の設定(`~/.config/hypr/hyprland.lua`)に `o.window(".*\\.exe", { float = true })` を足してください。
  - 液晶タブレットのペンの位置が大きくずれるときは、ペンをその画面だけに割り当ててください。
    例: `hl.config({ input = { tablet = { output = "DP-1" } } })`(画面の名前は `hyprctl monitors` で確かめられます)。
  - 窓の移動と最大化は、Hyprland の側(Hyprland のタイトルバー、または Super+F など)で行ってください。
    CLIP STUDIO PAINT 自身の最大化ボタンやタイトルバーのダブルクリックは、Omarchy では窓の中ではみ出したり、窓を動かせなくなったりします。
  - Omarchy の floating モードでは、メニューの項目が、マウスを乗せただけではハイライトされません(クリックすると選べます)。
- **画面が出ない・固まった**: 端末コマンド `clistux stop` で CLIP STUDIO PAINT と Wine を強制終了できます。その後もう一度起動してください。失われたデータがある場合でも保障はありませんので、自己責任でバックアップを欠かさないようにしてください。

## 削除する

端末で `clistux` と入力し、「6」を選んでください。このツールで設置した内容(アプリのメニュー、Wine、CLIP STUDIO PAINT 本体と設定)をすべて消すことができます。

- 本体と設定については、消すかどうかの確認が最後に表示されます。
- 「ドキュメント」フォルダに保存した作品は、ふつうは Linux の「ドキュメント」フォルダにあるので消えません。
  CLIP STUDIO PAINT 専用の環境の中に作品がある場合は、削除の前に警告が出ます。その場合は、先にほかの場所へ写してください。

## 仕組み

- Wine 11 に、CLIP STUDIO PAINT のために必要な修正(パッチ)を加えたものを使います。パッチとビルドの方法は `wine/` にあります。
- CLIP STUDIO PAINT 専用の Wine の環境(プレフィックス)を `~/.local/share/clistux/` に作ります。ほかの Wine の環境には触れません。
- Web の画面に使う部品(Microsoft Edge WebView2)は、Microsoft が頒布しているバージョンを入手し、内部で動作を確かめてから使います。
- 詳しくは [仕様書](docs/spec.md) と [調査の記録](docs/research.md) をご覧ください。

## ライセンス

- このツール: [GNU General Public License v3.0 以降](LICENSE)
- Wine へのパッチと、それを当ててビルドした Wine: Wine と同じ [GNU Lesser General Public License v2.1 以降](wine/COPYING.LIB)。
  ソースとパッチは、各リリースに添付しています。

CLIP STUDIO PAINT と CLIP STUDIO TABMATE は株式会社セルシスの製品・商標です。Microsoft Edge WebView2 は Microsoft の製品です。

## 謝辞

- [Wine](https://www.winehq.org/) の開発者のみなさん
- 調査の参考にした [CSPenguin](https://github.com/parka6060/CSPenguin-Installer) ほか、Linux で CLIP STUDIO PAINT を動かす取り組みをしてきたみなさん

---

## English

Clistux Installer sets up the Windows version of CLIP STUDIO PAINT on Linux with a patched Wine,
including Japanese input, pen pressure, CLIP STUDIO TABMATE and the WebView2-based pages.
It is an unofficial tool, not affiliated with CELSYS. CLIP STUDIO PAINT itself is not included.

```sh
curl -fsSL https://github.com/neatsorg/clistux-installer/releases/latest/download/install.sh | bash
```

Download the Windows installer of CLIP STUDIO PAINT from the official site first. After installation, run `clistux` for the menu
(update, diagnose and repair, migrate from other setups, uninstall). The tool is licensed under GPL-3.0-or-later;
the Wine patches under LGPL-2.1-or-later.
