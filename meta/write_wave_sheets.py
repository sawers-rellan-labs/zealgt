#!/usr/bin/env python3
"""Split meta/samples.csv into the production demultiplex waves (docs/runs/demultiplex_production.md).

Libraries are taken in samples.csv order and filled into a wave up to a cap of work/ peak, never splitting a library and
never mixing sources. work/ peak = raw bytes x a factor per source: fqtk lanes 0.85 + lane joins 0.85 if more than one lane
(bc1, batch 1) + tar members extracted 1.0 (batch 1). Raw bytes: the *.fq.gz in each raw_location (one ssh call to hazel),
batch 1 from meta/sources/bc2s3_batch1_tar_members.tsv.

Usage: python3 meta/write_wave_sheets.py [cap TB, default 2.0]
       prints the wave table and writes meta/waves/demultiplex_<NN>.csv, the samples.csv rows of each wave, unchanged
"""
import csv, os, subprocess, sys, collections
HERE = os.path.dirname(os.path.abspath(__file__))
CAP_TB = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0
FACTOR = {'bc1': 1.7, 'bc2s3_batch2': 0.85, 'bc2s3_batch1': 2.7}

with open(os.path.join(HERE, 'samples.csv'), newline='') as f:
    reader = csv.DictReader(f)
    header, rows = reader.fieldnames, list(reader)
libs = {}  # library -> [source, raw_location, kept samples]
for r in rows:
    lib = libs.setdefault(r['library'], [r['source'], r['raw_location'], 0])
    lib[2] += r['exclude'].strip().upper() == 'FALSE'

# plain-lane libraries: bytes of *.fq.gz per raw_location
plain = sorted({loc for s, loc, _ in libs.values() if s != 'bc2s3_batch1'})
cmd = 'for d in ' + ' '.join(plain) + '; do echo "$d $(find "$d" -maxdepth 1 -name "*.fq.gz" -printf "%s\\n" | awk "{s+=\\$1} END{print s+0}")"; done'
out = subprocess.run(['ssh', 'hazel', cmd], capture_output=True, text=True, check=True).stdout
size_by_dir = {l.split()[0]: int(l.split()[1]) for l in out.splitlines() if l.strip()}

# batch 1: tar member bytes by library prefix BZea<n>_
tar = collections.Counter()
with open(os.path.join(HERE, 'sources', 'bc2s3_batch1_tar_members.tsv')) as f:
    for l in f:
        size, name = l.rstrip('\n').split('\t')
        tar[name.split('/')[-1].split('_')[0]] += int(size)

waves, cur = [], None
for lib in dict.fromkeys(r['library'] for r in rows):
    s, loc, k = libs[lib]
    raw = tar[lib] if s == 'bc2s3_batch1' else size_by_dir.get(loc, 0)
    if not raw:
        sys.exit(f'no raw size for library {lib}')
    peak = raw * FACTOR[s]
    if cur is None or cur['source'] != s or (cur['peak'] + peak) / 1e12 > CAP_TB:
        cur = {'source': s, 'libs': [], 'raw': 0, 'peak': 0, 'samples': 0}
        waves.append(cur)
    cur['libs'].append(lib); cur['raw'] += raw; cur['peak'] += peak; cur['samples'] += k

os.makedirs(os.path.join(HERE, 'waves'), exist_ok=True)
print(f'| wave | source | libraries | kept samples | raw TB | work/ peak TB | final TB |  (cap {CAP_TB} TB)')
for i, w in enumerate(waves, 1):
    with open(os.path.join(HERE, 'waves', f'demultiplex_{i:02d}.csv'), 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=header, lineterminator='\r\n')
        writer.writeheader()
        writer.writerows(r for r in rows if r['library'] in w['libs'])
    names = w['libs'][0] + ('-' + w['libs'][-1] if len(w['libs']) > 1 else '') + f" ({len(w['libs'])})"
    print(f"| {i:02d} | {w['source']} | {names} | {w['samples']} | {w['raw']/1e12:.2f} | {w['peak']/1e12:.2f} | {w['raw']*0.85/1e12:.2f} |")
