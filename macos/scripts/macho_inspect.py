"""Read-only arm64 inspection for the locally installed, user-owned engine.

No binary patches. Disassembly remains in ignored .build/research, never bundled.
"""
import argparse
import bisect
import json
from pathlib import Path
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
IMAGE = ROOT / '.build/research/game_plugin.arm64'
MAP = ROOT / '.build/research/macho-map.json'

def image():
    data = IMAGE.read_bytes()
    meta = json.loads(MAP.read_text())
    return data, meta

def function(meta, address):
    starts = meta['functions']
    i = bisect.bisect_right(starts, address) - 1
    return starts[i], starts[i+1]

def refs(data, meta, targets, stores=False):
    section = next(s for s in meta['sections'] if s[0] == '__text')
    code = data[section[3]:section[3]+section[2]]
    pages = {a & ~4095 for a in targets}
    for i, (op,) in enumerate(struct.iter_unpack('<I', code)):
        if op & 0x9f000000 != 0x90000000:
            continue
        imm = (((op >> 5) & 0x7ffff) << 2) | ((op >> 29) & 3)
        if imm & (1 << 20):
            imm -= 1 << 21
        pc = section[1]+4*i
        page = (pc & ~4095)+(imm << 12)
        if page not in pages:
            continue
        rd = op & 31
        for d in range(1, min(512 if stores else 9, len(code)//4-i)):
            ins = struct.unpack_from('<I', code, 4*(i+d))[0]
            rn = (ins >> 5) & 31
            target = None
            if rn == rd and ins & 0xff000000 == 0x91000000:
                target = page + (((ins >> 10) & 4095) << (12 if (ins >> 22) & 1 else 0))
            elif rn == rd and ins & 0xffc00000 in (0xf9400000, 0xf9000000):
                target = page + (((ins >> 10) & 4095)*8)
            if target in targets and (not stores or ins & 0xffc00000 == 0xf9000000):
                yield pc + 4*d, target
            # Conservative liveness: a load/add to rd invalidates the page;
            # calls also clobber caller-saved registers. Stores do not write Rt.
            store = ins & 0x3b000000 == 0x39000000 and not (ins & (1 << 22))
            if ((ins & 31) == rd and not store) or (rd < 19 and ins & 0xfc000000 == 0x94000000):
                break

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['strings', 'refs', 'callers', 'disasm', 'pointers'])
    parser.add_argument('values', nargs='+')
    parser.add_argument('--limit', type=int, default=180)
    parser.add_argument('--stores', action='store_true')
    args = parser.parse_args()
    data, meta = image()
    if args.action == 'strings':
        pattern = re.compile(args.values[0], re.I)
        section = next(s for s in meta['sections'] if s[0] == '__cstring')
        found = 0
        for m in re.finditer(rb'[ -~]{4,}', data[section[3]:section[3]+section[2]]):
            value = m.group().decode()
            if pattern.search(value):
                print(hex(section[1]+m.start()), value)
                found += 1
                if found >= args.limit: break
        return
    addresses = {int(v, 0) for v in args.values}
    if args.action == 'refs':
        for count, (pc, target) in enumerate(refs(data, meta, addresses, args.stores)):
            if count >= args.limit:
                print('Output capped at', args.limit)
                break
            start, end = function(meta, pc)
            print(hex(pc), '->', hex(target), 'function', hex(start), hex(end))
    elif args.action == 'disasm':
        for addr in sorted(addresses):
            start, end = function(meta, addr)
            r = subprocess.run(['/Library/Developer/CommandLineTools/usr/bin/llvm-objdump',
                '--disassemble', f'--start-address={start}', f'--stop-address={end}', str(IMAGE)], capture_output=True, text=True, check=True)
            out = ROOT / f'.build/research/fn-{start:x}.txt'
            out.write_text(r.stdout)
            print(out)
            print('\n'.join(r.stdout.splitlines()[:args.limit]))
    elif args.action == 'callers':
        section = next(s for s in meta['sections'] if s[0] == '__text')
        for i, (ins,) in enumerate(struct.iter_unpack('<I', data[section[3]:section[3]+section[2]])):
            if ins & 0x7c000000 != 0x14000000: continue
            imm = ins & 0x3ffffff
            if imm & (1 << 25): imm -= 1 << 26
            pc = section[1] + i*4
            if pc + imm*4 in addresses:
                start, end = function(meta, pc)
                print(hex(pc), '->', hex(pc+imm*4), 'function', hex(start), hex(end))
    else:
        for address in addresses:
            needle = struct.pack('<Q', address)
            i = data.find(needle)
            while i >= 0:
                print(hex(i), '->', hex(address))
                i = data.find(needle, i+1)

if __name__ == '__main__':
    main()
