# -*- coding: utf-8 -*-
"""登录/选服界面 locres 覆盖（最小叠加，不碰 pak / 不改官方文件）

机制与第三方工具一致：
  Engine/Content/Localization/Engine/Platforms/Windows/<culture>/Engine.locres
只写登录/选服相关键；回退 = 删掉这两个文件。

用法：
  python aion2_login_locres.py            # 生成到 _staging 并打印校验（默认明文简体）
  python aion2_login_locres.py --install  # 生成并复制进游戏
  python aion2_login_locres.py --revert   # 从游戏删除
  python aion2_login_locres.py --minimal  # 只写 88 条登录键 × 26 个候选命名空间
  python aion2_login_locres.py --carrier  # 改用游戏内载体字文本（会显示成载体字，勿用于背景登录界面）
"""
import os
import sys
import json
import struct
import zlib
import shutil

from Crypto.Cipher import AES
import lz4.block

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

STAGING = os.path.join(HERE, '_staging_login')
GAME = r'F:\SteamLibrary\steamapps\common\Aion2'
GAME_LOC = os.path.join(GAME, r'Engine\Content\Localization')

ZH_PAK = os.path.join(HERE, r'_work_en\out\zh_text.pak')
EN_SRC = os.path.join(HERE, r'_work_en\en_src.json')
# 明文简体表（153008 条，纯明文，无载体字）；可用环境变量 PLAIN_DAT 指向繁体表
PLAIN_DAT = os.environ.get('PLAIN_DAT') or os.path.join(HERE, r'_work_en\out\plain_zh.dat')

KEY_EN = bytes.fromhex('38efed84543f7324fa6e8f4b84b2ec8fc8debd65f1b5ac2ef0e215d929cd63d3')
MASK_EN = bytes.fromhex('df3b56b94c3bfbac3db122e2978e3c7b')
PREFIX_EN = bytes.fromhex('f0a22b661dee0bb8996a05bfe4a930c76c691faaf96b63404882521df6e9077c')

MAGIC = bytes.fromhex('0e147475674a03fc4a15909d337f1b'.replace('337f1b', 'c3377f1b'))
DAT_LEN = 3980468

# 覆盖的命名空间候选（工具无法得知游戏内部 namespace，一次全铺）
NS_CANDIDATES = [
    '', 'AION2', 'Aion2', 'aion2', 'AION', 'Aion', 'AION2UI', 'Aion2UI',
    'UI', 'Game', 'Lobby', 'String', 'StringTable', 'L10N', 'L10NString',
    'Text', 'Message', 'MessageTable', 'Table', 'StartUpData', 'GlobalService',
    'Engine', 'Client', 'Aion2Table', 'String_UI', 'NCSOFT',
]


# ---------------------------------------------------------------- dat 读写
def decode_dat(blob):
    enc_type, aligned, packed, raw = struct.unpack(
        '<iiii', bytes(blob[4 + i] ^ MASK_EN[i] for i in range(16)))
    assert enc_type == 2 and aligned % 16 == 0 and aligned + 20 <= len(blob), \
        (enc_type, aligned, packed, raw, len(blob))
    dec = AES.new(KEY_EN, AES.MODE_ECB).decrypt(blob[20:20 + aligned])
    assert dec[:32] == PREFIX_EN, 'en-US 前缀不符'
    return lz4.block.decompress(dec[32:32 + packed], uncompressed_size=raw)


def r_fstr(b, p):
    n = struct.unpack_from('<i', b, p)[0]
    p += 4
    if n == 0:
        return '', p
    if n > 0:
        return b[p:p + n - 1].decode('utf-8', 'replace'), p + n
    c = -n
    return b[p:p + c * 2 - 2].decode('utf-16-le', 'replace'), p + c * 2


def parse_table(body):
    ver = struct.unpack_from('<i', body, 0)[0]
    ns, p = r_fstr(body, 4)
    cnt = struct.unpack_from('<i', body, p)[0]
    p += 4
    rows = []
    for _ in range(cnt):
        k, p = r_fstr(body, p)
        v, p = r_fstr(body, p)
        rows.append((k, v))
    return ver, ns, cnt, rows


def load_rows(path, dat_mode):
    raw = open(path, 'rb').read()
    if dat_mode:
        dat = raw[53:]
    else:
        assert len(raw) >= 53 + DAT_LEN, (len(raw), DAT_LEN)
        dat = raw[53:53 + DAT_LEN]
    body = decode_dat(dat)
    ver, ns, cnt, rows = parse_table(body)
    return ns, cnt, dict(rows)


# ---------------------------------------------------------------- locres 写
def w_u32(v):
    return struct.pack('<I', v & 0xFFFFFFFF)


def w_str(s):
    if s == '':
        return w_u32(0)
    if all(ord(c) < 128 for c in s):
        b = s.encode('ascii')
        return w_u32(len(b) + 1) + b + b'\0'
    u = s.encode('utf-16-le')
    return struct.pack('<i', -(len(s) + 1)) + u + b'\0\0'


def src_hash(s):
    """UE SourceStringHash：CRC32(UTF-32LE)"""
    return zlib.crc32(b''.join(bytes([c, 0, 0, 0]) for c in s.encode('utf-8'))) & 0xFFFFFFFF


def build_locres(groups):
    """groups: [(namespace, [(key, en_source, text)])]"""
    strings, index = [], {}
    for _, entries in groups:
        for _, _, t in entries:
            if t not in index:
                index[t] = len(strings)
                strings.append(t)

    out = bytearray()
    out += MAGIC
    out += bytes([1])
    out += b'\0' * 8
    out += w_u32(len(groups))
    for ns, entries in groups:
        out += w_str(ns)
        out += w_u32(len(entries))
        for k, src, t in entries:
            out += w_str(k)
            out += w_u32(src_hash(src))
            out += w_u32(index[t])
    str_off = len(out)
    out += w_u32(len(strings))
    for s in strings:
        out += w_str(s)
    struct.pack_into('<Q', out, 17, str_off)
    return bytes(out)


def parse_locres(buf):
    assert buf[:16] == MAGIC
    ver = buf[16]
    str_off = struct.unpack_from('<Q', buf, 17)[0]
    p = 25
    nsc = struct.unpack_from('<I', buf, p)[0]
    p += 4
    got = []
    for _ in range(nsc):
        name, p = r_fstr(buf, p)
        c = struct.unpack_from('<I', buf, p)[0]
        p += 4
        for _ in range(c):
            k, p = r_fstr(buf, p)
            p += 8
        got.append((name, c))
    assert p == str_off, (p, str_off)
    n = struct.unpack_from('<I', buf, str_off)[0]
    q = str_off + 4
    strs = []
    for _ in range(n):
        s, q = r_fstr(buf, q)
        strs.append(s)
    assert q == len(buf), (q, len(buf))
    return ver, got, strs


def pick_keys(rows_zh):
    sel = []
    for k in rows_zh:
        ku = k.upper()
        if 'GLOBAL_SERVICE' in ku or 'SERVER_REGION' in ku:
            sel.append(k)
        elif ku.startswith('STRING_UI_LOGIN') or ku.startswith('STRING_STR_LOGIN'):
            sel.append(k)
    return sorted(set(sel))


def load_plain():
    """读取明文简体表（ja-JP 容器编码），返回 {key: 简体中文}"""
    import aion2_l10n as L
    _, body = L.decode_dat(open(PLAIN_DAT, 'rb').read(), 'ja-JP')
    _, ns, cnt, rows = L.parse_table(body)
    print('明文表 ns=%r rows=%d' % (ns, cnt))
    return dict(rows)


def main():
    # 默认用明文简体：登录界面字体自带完整 CJK cmap，原生简体字可直接渲染。
    # （载体字只适用于游戏内 dat 文本通道，用在 locres 上会显示成载体字本字）
    plain = '--carrier' not in sys.argv
    if plain:
        zh = load_plain()
    else:
        _, _, zh = load_rows(ZH_PAK, dat_mode=False)
    en = json.load(open(EN_SRC, encoding='utf-8'))
    keys = pick_keys(zh)
    minimal = '--minimal' in sys.argv

    if minimal:
        entries = [(k, en.get(k, ''), zh[k]) for k in keys if zh.get(k)]
        groups = [(ns, entries) for ns in NS_CANDIDATES]
        print('保守模式：%d 条登录键 × %d 个命名空间' % (len(entries), len(groups)))
    else:
        full = [(k, en.get(k, ''), zh[k]) for k in sorted(zh)]
        login = [(k, en.get(k, ''), zh[k]) for k in keys if zh.get(k)]
        groups = [('AION2', full)]
        groups += [(ns, login) for ns in NS_CANDIDATES if ns != 'AION2']
        print('全量模式：AION2 命名空间写 %d 条；另 %d 条登录键铺 %d 个备选命名空间'
              % (len(full), len(login), len(groups) - 1))
    for k, s, t in groups[0][1][:5]:
        print('  %-58s %s' % (k, t[:24]))

    blob = build_locres(groups)
    ver, nss, strs = parse_locres(blob)
    print('locres: %.2f MB  ver=%d ns=%d strings=%d total=%d'
          % (len(blob) / 1048576, ver, len(nss), len(strs), sum(c for _, c in nss)))

    if os.path.isdir(STAGING):
        shutil.rmtree(STAGING)
    for c in ('en', 'en-US'):
        d = os.path.join(STAGING, 'Localization', 'Engine', 'Platforms', 'Windows', c)
        os.makedirs(d)
        open(os.path.join(d, 'Engine.locres'), 'wb').write(blob)
    print('已生成: %s' % STAGING)

    if '--revert' in sys.argv:
        if os.path.isdir(GAME_LOC):
            shutil.rmtree(GAME_LOC)
            print('已删除 %s' % GAME_LOC)
        else:
            print('游戏里没有 %s' % GAME_LOC)
        return

    if '--install' in sys.argv:
        dst_root = os.path.join(GAME_LOC, 'Engine', 'Platforms', 'Windows')
        for c in ('en', 'en-US'):
            d = os.path.join(dst_root, c)
            os.makedirs(d, exist_ok=True)
            shutil.copyfile(os.path.join(STAGING, 'Localization', 'Engine', 'Platforms',
                                         'Windows', c, 'Engine.locres'),
                            os.path.join(d, 'Engine.locres'))
            print('已安装 %s (%d B)' % (os.path.join(d, 'Engine.locres'),
                                        os.path.getsize(os.path.join(d, 'Engine.locres'))))


if __name__ == '__main__':
    main()
