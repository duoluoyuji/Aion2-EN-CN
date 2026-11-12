# -*- coding: utf-8 -*-
"""
对比：官方快照 vs 中文语料，列出「新增 / 待翻译」的 key。
用法: python aion2_diff.py [快照json] [语料dat]
"""
import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import aion2_l10n as L

SNAP_DIR = os.path.join(HERE, '_snapshots')
PLAIN = os.path.join(HERE, r'_work_en\out\plain_zh.dat')

def load_snap(p):
    d = json.load(open(p, encoding='utf-8'))
    return d['meta'], d['rows']

def load_corpus(p):
    _, body = L.decode_dat(open(p, 'rb').read(), 'ja-JP')
    _, ns, cnt, rows = L.parse_table(body)
    return dict(rows)

snaps = sorted(f for f in os.listdir(SNAP_DIR) if f.endswith('.json')) if os.path.isdir(SNAP_DIR) else []
snap_path = sys.argv[1] if len(sys.argv) > 1 else (os.path.join(SNAP_DIR, snaps[-1]) if snaps else None)
corpus_path = sys.argv[2] if len(sys.argv) > 2 else PLAIN
if not snap_path:
    raise SystemExit('没有快照')

meta, en = load_snap(snap_path)
zh = load_corpus(corpus_path)
print('快照 : %s  rows=%d' % (meta['sha256'][:16], meta['rows']))
print('语料 : %d 条' % len(zh))
missing = [k for k in en if k not in zh]
extra = [k for k in zh if k not in en]
print('待翻译(新 key) = %d' % len(missing))
print('语料多余(已删) = %d' % len(extra))
for k in missing[:15]:
    print('  + %-72s %r' % (k, en[k].replace('\n', ' ')[:60]))
