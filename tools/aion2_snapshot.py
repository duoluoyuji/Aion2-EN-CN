# -*- coding: utf-8 -*-
"""
从游戏目录里的官方 en-US 包，只读提取全表（key + 英文原文），存成快照。
用法: python aion2_snapshot.py [pak路径]
"""
import sys, os, json, struct, hashlib, datetime
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aion2_l10n as L
from Crypto.Cipher import AES
import lz4.block as lb

KEY_EN = bytes.fromhex('38efed84543f7324fa6e8f4b84b2ec8fc8debd65f1b5ac2ef0e215d929cd63d3')
MASK_EN = bytes.fromhex('df3b56b94c3bfbac3db122e2978e3c7b')
DEFAULT = r'F:\SteamLibrary\steamapps\common\Aion2\Aion2\Content\Paks\L10N\Text\en-US\pakchunk502000-Windows_0_P.pak'
OUTDIR = os.path.join(HERE, '_snapshots')

pak = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
raw = open(pak, 'rb').read()
print('输入: %s' % pak)
print('大小: %d B   sha256: %s' % (len(raw), hashlib.sha256(raw).hexdigest()[:16]))

# --- 定位 dat：pak 数据区偏移，扫描头部特征 ---
def find_dat(raw):
    for p in range(0, 8192):
        if raw[p:p + 4] != b'\x02\x00\x00\x00':
            continue
        try:
            enc, aligned, packed, rawlen = struct.unpack(
                '<iiii', bytes(raw[p + 4 + i] ^ MASK_EN[i] for i in range(16)))
        except Exception:
            continue
        if enc == 2 and 0 < aligned <= len(raw) and 0 < packed <= aligned and 0 < rawlen < 64 * 1024 * 1024:
            return p, raw[p:p + 20 + aligned], (aligned, packed, rawlen)
    return None, None, None

off, dat, info = find_dat(raw)
if not dat:
    raise SystemExit('未找到 dat 容器')
print('dat 偏移=%d  aligned=%d packed=%d raw=%d' % (off, *info))

dec = AES.new(KEY_EN, AES.MODE_ECB).decrypt(dat[20:20 + info[0]])
body = lb.decompress(dec[32:32 + info[1]], uncompressed_size=info[2])
ver, ns, cnt, rows = L.parse_table(body)
print('命名空间=%r  条数=%d' % (ns, cnt))

os.makedirs(OUTDIR, exist_ok=True)
stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M')
out = os.path.join(OUTDIR, 'en_snapshot_%s.json' % stamp)
json.dump({'meta': {'source': pak, 'size': len(raw),
                    'sha256': hashlib.sha256(raw).hexdigest(),
                    'namespace': ns, 'rows': cnt, 'time': stamp},
           'rows': dict(rows)}, open(out, 'w', encoding='utf-8'), ensure_ascii=False)
print('快照已存: %s  %.1f MB' % (out, os.path.getsize(out) / 1048576))

for k, v in rows[:3]:
    print('  %-70s %r' % (k, v))
nonascii = sum(1 for k, v in rows if any(ord(c) > 126 for c in v))
print('英文原文含非 ASCII 的条数 =', nonascii)
