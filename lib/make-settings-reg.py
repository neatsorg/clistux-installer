#!/usr/bin/env python3
# CSP 用の設定を、1つの .reg ファイル(regedit が読む UTF-16 の形式)にまとめる。
# 設定は CSP の版ではなく exe の名前に結びつけるので、CSP を更新しても同じものを入れ直せばよい(spec 設計の三本柱 1)。
#
# 使い方:
#   make-settings-reg.py --out 出力.reg --prefix プレフィックス --applied 記録.json --mode full|preserve
#                        [--gothic 候補;…] [--mincho 候補;…] [--disable サービス;…]
#   --gothic/--mincho  この PC に実際にあるフォントの名前だけを、優先する順に渡す
#   --disable          止めるサービス(プレフィックスに登録されているものだけ。無いサービスのキーを作らないため)
#   --mode full        すべての値を入れる(導入・修復)
#   --mode preserve    利用者が変えた値は残す(更新)。今の値が、このツールが前回入れた値(--applied)と違えば入れない
# 出力: .reg と、記録の新しい版(<記録>.new)。残した値は「KEPT<TAB>キー<TAB>名前」として標準出力に書く。
# 記録の新しい版は、呼び出し側が regedit の成功後に記録へ置き換える。
import argparse
import json
import os
import re

ap = argparse.ArgumentParser()
ap.add_argument('--out', required=True)
ap.add_argument('--prefix', required=True)
ap.add_argument('--applied', required=True)
ap.add_argument('--mode', choices=['full', 'preserve'], required=True)
ap.add_argument('--gothic', default='')
ap.add_argument('--mincho', default='')
ap.add_argument('--disable', default='')
args = ap.parse_args()

gothic = [f for f in args.gothic.split(';') if f]
mincho = [f for f in args.mincho.split(';') if f] or gothic   # 明朝体が無ければゴシック体で代用する
disable_services = [s for s in args.disable.split(';') if s]

HKLM = 'HKEY_LOCAL_MACHINE'
HKCU = 'HKEY_CURRENT_USER'

# ---- 入れたい値 -------------------------------------------------------------------
# (キー, 名前, 型, 値)。型は sz(文字列)・dword(数)・multi(文字列の並び)
desired = []


def put(key, name, kind, value):
    desired.append((key, name, kind, value))


# 4.5 Windows のバージョンの見せ方
#   CLIPStudio.exe: Windows 8.1(WebView2 をウィンドウ方式で使わせる)
#   msedgewebview2.exe: Windows 7(Chromium に DirectComposition を使わせない)
#   CLIPStudioPaint.exe: 初期値(Windows 10)のまま
put(rf'{HKCU}\Software\Wine\AppDefaults\CLIPStudio.exe', 'Version', 'sz', 'win81')
put(rf'{HKCU}\Software\Wine\AppDefaults\msedgewebview2.exe', 'Version', 'sz', 'win7')

# WinRT のクラス(パッチ 0005 のスタブ)。CSP の triglavwinrt.dll がホイール型デバイスの準備で使う。
for cls, dll in [('Windows.UI.Input.RadialController', 'windows.ui.dll'),
                 ('Windows.UI.Input.RadialControllerConfiguration', 'windows.ui.dll'),
                 ('Windows.UI.Input.RadialControllerMenuItem', 'windows.ui.dll'),
                 ('Windows.Storage.StorageFile', 'windows.storage.dll')]:
    put(rf'{HKLM}\Software\Microsoft\WindowsRuntime\ActivatableClassId\{cls}', 'DllPath', 'sz',
        rf'C:\windows\system32\{dll}')

# 4.7 日本語フォント: Windows のフォントが無いときだけ効く置き換え
GOTHIC_NAMES = ['MS UI Gothic', 'MS Gothic', 'MS PGothic', 'Meiryo', 'Meiryo UI', 'Yu Gothic', 'Yu Gothic UI',
                'ＭＳ ゴシック', 'ＭＳ Ｐゴシック', 'メイリオ', '游ゴシック']
MINCHO_NAMES = ['MS Mincho', 'MS PMincho', 'Yu Mincho', 'ＭＳ 明朝', 'ＭＳ Ｐ明朝', '游明朝']
if gothic:
    for n in GOTHIC_NAMES:
        put(rf'{HKCU}\Software\Wine\Fonts\Replacements', n, 'multi', gothic)
    for n in MINCHO_NAMES:
        put(rf'{HKCU}\Software\Wine\Fonts\Replacements', n, 'multi', mincho)

# 8. CLIP STUDIO TABMATE: winebus に、TABMATE を hidraw のまま CSP に渡させる
put(rf'{HKLM}\System\CurrentControlSet\Services\winebus', 'Enable SDL', 'dword', 0)
put(rf'{HKLM}\System\CurrentControlSet\Services\winebus', 'DisableInput', 'dword', 1)
# PlugPlay は有効のまま(Wine の初期値)。無効だと、CSP の起動後につないだ TABMATE を拾えない。
put(rf'{HKLM}\System\CurrentControlSet\Services\PlugPlay', 'Start', 'dword', 2)

# WebView2 の自動更新のサービス(CSP のインストーラが WebView2 と一緒に入れる)を止める。
# 動かしておくと Wine を起動するたびに常駐し、CSP を閉じても Wine が終わらない。
# WebView2 は、このツールが版固定のものを入れて使わせる(lib/webview2.sh)。
for svc in disable_services:
    put(rf'{HKLM}\System\CurrentControlSet\Services\{svc}', 'Start', 'dword', 4)


# ---- 今の値(プレフィックスのレジストリのファイルを読む) -------------------------
def unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c != '\\' or i + 1 >= len(s):
            out.append(c)
            i += 1
            continue
        n = s[i + 1]
        if n == 'x':
            m = re.match(r'[0-9a-fA-F]{1,4}', s[i + 2:])
            if m:
                out.append(chr(int(m.group(0), 16)))
                i += 2 + len(m.group(0))
                continue
        out.append({'0': '\0', 'n': '\n', 'r': '\r', 't': '\t'}.get(n, n))
        i += 2
    return ''.join(out)


def parse_value(raw):
    if raw.startswith('dword:'):
        return 'dword', int(raw[6:], 16)
    m = re.match(r'(?:str\((\d)\):)?"(.*)"$', raw)
    if m:
        text = unescape(m.group(2))
        if m.group(1) == '7':
            return 'multi', [x for x in text.split('\0') if x]
        return 'sz', text
    m = re.match(r'hex\(7\):(.*)$', raw)
    if m:
        data = bytes(int(h, 16) for h in m.group(1).replace('\\', '').replace(' ', '').split(',') if h)
        return 'multi', [x for x in data.decode('utf-16-le').split('\0') if x]
    return 'other', raw


def file_and_section(key):
    if key.startswith(HKCU + '\\'):
        return 'user.reg', key[len(HKCU) + 1:]
    rest = key[len(HKLM) + 1:]
    rest = re.sub(r'^System\\CurrentControlSet\\', r'System\\ControlSet001\\', rest, flags=re.I)
    return 'system.reg', rest


_cache = {}


def registry(fname):
    if fname in _cache:
        return _cache[fname]
    sections, cur, pending = {}, None, ''
    try:
        lines = open(os.path.join(args.prefix, fname), encoding='utf-8', errors='replace').read().split('\n')
    except OSError:
        lines = []
    for line in lines:
        if pending:
            line, pending = pending + line.strip(), ''
        if line.endswith('\\') and not line.endswith('\\\\'):
            pending = line[:-1]
            continue
        if line.startswith('['):
            m = re.match(r'\[(.*)\](?:\s+\d+)?$', line)
            cur = unescape(m.group(1)).lower() if m else None
            sections.setdefault(cur, {})
            continue
        if cur is None or not line.startswith('"'):
            continue
        m = re.match(r'"((?:[^"\\]|\\.)*)"=(.*)$', line)
        if m:
            sections[cur][unescape(m.group(1)).lower()] = parse_value(m.group(2))
    _cache[fname] = sections
    return sections


def current(key, name):
    fname, section = file_and_section(key)
    return registry(fname).get(section.lower(), {}).get(name.lower())


# ---- 前回このツールが入れた値 ----------------------------------------------------
def ident(key, name):
    return key.lower() + '\0' + name.lower()


try:
    applied = {ident(k, n): (t, v) for k, n, t, v in json.load(open(args.applied, encoding='utf-8'))}
    have_record = True
except (OSError, ValueError):
    applied, have_record = {}, False


def same(a, b):
    return a is not None and b is not None and a[0] == b[0] and a[1] == b[1]


# ---- 入れる値を決める -------------------------------------------------------------
write, record = [], []
for key, name, kind, value in desired:
    want = (kind, value)
    if args.mode == 'full' or not have_record:
        ok = True
    else:
        cur = current(key, name)
        prev = applied.get(ident(key, name))
        # 値が無い・すでに同じ・前回このツールが入れた値のまま なら入れる。それ以外は利用者が変えたとみなして残す
        ok = cur is None or same(cur, want) or same(cur, prev)
    if ok:
        write.append((key, name, kind, value))
        record.append([key, name, kind, value])
    else:
        print(f'KEPT\t{key}\t{name}')
        prev = applied.get(ident(key, name))
        if prev is not None:
            record.append([key, name, prev[0], prev[1]])


# ---- .reg と記録を書く ------------------------------------------------------------
def reg_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def reg_value(kind, value):
    if kind == 'dword':
        return f'dword:{value:08x}'
    if kind == 'multi':
        data = ''.join(i + '\0' for i in value) + '\0'
        return 'hex(7):' + ','.join(f'{b:02x}' for b in data.encode('utf-16-le'))
    return reg_str(value)


keys = {}
for key, name, kind, value in write:
    keys.setdefault(key, []).append(f'{reg_str(name)}={reg_value(kind, value)}')
lines = ['Windows Registry Editor Version 5.00', '']
for key, values in keys.items():
    lines.append(f'[{key}]')
    lines.extend(values)
    lines.append('')
with open(args.out, 'w', encoding='utf-16', newline='\r\n') as f:
    f.write('\n'.join(lines) + '\n')
with open(args.applied + '.new', 'w', encoding='utf-8') as f:
    json.dump(record, f, ensure_ascii=False, indent=0)
