#!/usr/bin/env python3
# CSP 用の設定を、1つの .reg ファイル(regedit が読む UTF-16 の形式)にまとめる。
# 設定は CSP の版ではなく exe の名前に結びつけるので、CSP を更新しても同じものを入れ直せばよい(spec 設計の三本柱 1)。
#
# 使い方: make-settings-reg.py 出力先.reg ゴシック体の候補(; 区切り) 明朝体の候補(; 区切り) [止めるサービス(; 区切り)]
#   候補は、この PC に実際にあるフォントの名前だけを、優先する順に渡す。
#   止めるサービスは、プレフィックスに登録されているものだけを渡す(無いサービスのキーを作らないため)。
import sys

out, gothic, mincho = sys.argv[1], sys.argv[2], sys.argv[3]
disable_services = [s for s in (sys.argv[4] if len(sys.argv) > 4 else '').split(';') if s]
gothic = [f for f in gothic.split(';') if f]
mincho = [f for f in mincho.split(';') if f] or gothic   # 明朝体が無ければゴシック体で代用する

HKLM = 'HKEY_LOCAL_MACHINE'
HKCU = 'HKEY_CURRENT_USER'


def reg_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def multi_sz(items):
    data = ''.join(i + '\0' for i in items) + '\0'
    return 'hex(7):' + ','.join(f'{b:02x}' for b in data.encode('utf-16-le'))


keys = {}


def put(key, name, value):
    keys.setdefault(key, []).append(f'{reg_str(name)}={value}')


# 4.5 Windows のバージョンの見せ方
#   CLIPStudio.exe: Windows 8.1(WebView2 をウィンドウ方式で使わせる)
#   msedgewebview2.exe: Windows 7(Chromium に DirectComposition を使わせない)
#   CLIPStudioPaint.exe: 初期値(Windows 10)のまま
put(rf'{HKCU}\Software\Wine\AppDefaults\CLIPStudio.exe', 'Version', reg_str('win81'))
put(rf'{HKCU}\Software\Wine\AppDefaults\msedgewebview2.exe', 'Version', reg_str('win7'))

# WinRT のクラス(パッチ 0005 のスタブ)。CSP の triglavwinrt.dll がホイール型デバイスの準備で使う。
for cls, dll in [('Windows.UI.Input.RadialController', 'windows.ui.dll'),
                 ('Windows.UI.Input.RadialControllerConfiguration', 'windows.ui.dll'),
                 ('Windows.UI.Input.RadialControllerMenuItem', 'windows.ui.dll'),
                 ('Windows.Storage.StorageFile', 'windows.storage.dll')]:
    put(rf'{HKLM}\Software\Microsoft\WindowsRuntime\ActivatableClassId\{cls}', 'DllPath',
        reg_str(rf'C:\windows\system32\{dll}'))

# 4.7 日本語フォント: Windows のフォントが無いときだけ効く置き換え
GOTHIC_NAMES = ['MS UI Gothic', 'MS Gothic', 'MS PGothic', 'Meiryo', 'Meiryo UI', 'Yu Gothic', 'Yu Gothic UI',
                'ＭＳ ゴシック', 'ＭＳ Ｐゴシック', 'メイリオ', '游ゴシック']
MINCHO_NAMES = ['MS Mincho', 'MS PMincho', 'Yu Mincho', 'ＭＳ 明朝', 'ＭＳ Ｐ明朝', '游明朝']
if gothic:
    for n in GOTHIC_NAMES:
        put(rf'{HKCU}\Software\Wine\Fonts\Replacements', n, multi_sz(gothic))
    for n in MINCHO_NAMES:
        put(rf'{HKCU}\Software\Wine\Fonts\Replacements', n, multi_sz(mincho))

# 8. CLIP STUDIO TABMATE: winebus に、TABMATE を hidraw のまま CSP に渡させる
put(rf'{HKLM}\System\CurrentControlSet\Services\winebus', 'Enable SDL', 'dword:00000000')
put(rf'{HKLM}\System\CurrentControlSet\Services\winebus', 'DisableInput', 'dword:00000001')
# PlugPlay は有効のまま(Wine の初期値)。無効だと、CSP の起動後につないだ TABMATE を拾えない。
put(rf'{HKLM}\System\CurrentControlSet\Services\PlugPlay', 'Start', 'dword:00000002')

# WebView2 の自動更新のサービス(CSP のインストーラが WebView2 と一緒に入れる)を止める。
# 動かしておくと Wine を起動するたびに常駐し、CSP を閉じても Wine が終わらない。
# WebView2 は CSP のインストーラに同梱されていて、CSP の更新のときに新しくなる。
for svc in disable_services:
    put(rf'{HKLM}\System\CurrentControlSet\Services\{svc}', 'Start', 'dword:00000004')

lines = ['Windows Registry Editor Version 5.00', '']
for key, values in keys.items():
    lines.append(f'[{key}]')
    lines.extend(values)
    lines.append('')
with open(out, 'w', encoding='utf-16', newline='\r\n') as f:
    f.write('\n'.join(lines) + '\n')
