"""AION2 L10NString.dat 解码 / 编码（v2 容器，语言相关掩码与密钥）"""
import struct
import blake3
import lz4.block
from Crypto.Cipher import AES

HDR_CONST = 0xCD02190910CE83F6
ROOT64 = struct.unpack('<Q', blake3.blake3(struct.pack('<Q', HDR_CONST)).digest()[:8])[0]

KEYS = {
    'en-US': bytes.fromhex('0cfdab7bcb727e404a20577c83be3399207f02ab68c18f300d36fd3c66cb218e'),
    'ja-JP': bytes.fromhex('54ddbe7c73b9a3d6a20faf164a40b2be9b6b9b2275873088268e4bcfb891a06b'),
    'ko-KR': bytes.fromhex('9f942b531ef340cd89e8d6e5f76a9c30760fdbca4dcd82992bdfb36e57bff3f8'),
    'de-DE': bytes.fromhex('b8a594db77c5d81df42e8148db42f9e7a3255affa42db7f543619e725b693530'),
}

# 各语言正文 32 字节前缀（语言常量）
PREFIX = {
    'en-US': bytes.fromhex('fa4b2894f6c99abf3412f741232847d2292d3b339481bd6fd32bcc61e67a8776'),
    'ja-JP': bytes.fromhex('4785e9986a06e65b30c3c2cd030ed5fa9071d2d4cb9feece33a945a657757982'),
}


def seed(loc):
    return struct.unpack('<Q', blake3.blake3(('L10NString_' + loc).encode()).digest()[:8])[0]


def mask(seedv, kind=3):
    return blake3.blake3(struct.pack('<Q', ROOT64) + struct.pack('<Q', seedv)
                         + struct.pack('<i', kind) + b'\0' * 4).digest()


def decode_dat(blob, loc):
    m = mask(seed(loc))
    head = bytes(blob[4 + i] ^ m[i] for i in range(16))
    packed, enc, aligned, raw = struct.unpack('<iiii', head)
    if enc != 2 or aligned + 20 != len(blob) or aligned % 16:
        raise ValueError('头部不符: %s' % dict(packed=packed, enc=enc, aligned=aligned, raw=raw))
    dec = AES.new(KEYS[loc], AES.MODE_ECB).decrypt(blob[20:20 + aligned])
    body = lz4.block.decompress(dec[32:32 + packed], uncompressed_size=raw)
    return dec[:32], body


def encode_dat(body, loc, prefix=None):
    if prefix is None:
        prefix = PREFIX[loc]
    packed_buf = lz4.block.compress(body, store_size=False)
    packed = len(packed_buf)
    payload_len = 32 + packed
    aligned = (payload_len + 15) & ~15
    buf = bytearray(aligned)
    buf[0:32] = prefix
    buf[32:32 + packed] = packed_buf
    enc = AES.new(KEYS[loc], AES.MODE_ECB).encrypt(bytes(buf))
    m = mask(seed(loc))
    hdr = struct.pack('<iiii', packed, 2, aligned, len(body))
    out = bytearray(struct.pack('<i', 2))
    out += bytes(hdr[i] ^ m[i] for i in range(16))
    out += enc
    return bytes(out)


class Reader:
    def __init__(self, b):
        self.b, self.p = b, 0

    def i32(self):
        v = struct.unpack_from('<i', self.b, self.p)[0]
        self.p += 4
        return v

    def fstr(self):
        n = self.i32()
        if n == 0:
            return ''
        if n > 0:
            s = self.b[self.p:self.p + n]
            self.p += n
            return s[:-1].decode('utf-8', 'replace')
        s = self.b[self.p:self.p - 2 * n]
        self.p += -2 * n
        return s[:-2].decode('utf-16-le', 'replace')


def write_fstr(out, s):
    if not s:
        out += struct.pack('<i', 0)
        return
    if all(ord(c) < 128 for c in s):
        b = s.encode('ascii', 'replace')
        out += struct.pack('<i', len(b) + 1) + b + b'\0'
    else:
        b = s.encode('utf-16-le')
        out += struct.pack('<i', -(len(s) + 1)) + b + b'\0\0'


def parse_table(body):
    r = Reader(body)
    ver = r.i32()
    ns = r.fstr()
    cnt = r.i32()
    rows = []
    for _ in range(cnt):
        k = r.fstr()
        rows.append((k, r.fstr()))
    return ver, ns, cnt, rows


def build_table(ns, rows, ver=1):
    out = bytearray()
    out += struct.pack('<i', ver)
    write_fstr(out, ns)
    out += struct.pack('<i', len(rows))
    for k, v in rows:
        write_fstr(out, k)
        write_fstr(out, v)
    out += struct.pack('<i', 0)
    return bytes(out)
