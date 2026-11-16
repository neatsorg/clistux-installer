#!/usr/bin/env python3
# プレフィックスの system.reg / user.reg から、ユーザーのフォント(~/.local/share/fonts)を指す行を消す。
# 元のファイルは <名前>.before-nofont に控える(既にあれば上書きしない)。wineserver を止めてから実行する。
import shutil, sys, os
prefix = sys.argv[1]
for name in ('system.reg', 'user.reg'):
    p = os.path.join(prefix, name)
    if not os.path.exists(p + '.before-nofont'):
        shutil.copy2(p, p + '.before-nofont')
    lines = open(p, encoding='utf-8', errors='surrogateescape').read().split('\n')
    out = [l for l in lines if not (l.startswith('"') and 'local\\\\share\\\\fonts' in l)]
    open(p, 'w', encoding='utf-8', errors='surrogateescape').write('\n'.join(out))
    print(name, '消した行:', len(lines) - len(out))
