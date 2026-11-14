#!/usr/bin/env python3
# Dump the tags of a Qualcomm Bluetooth NVM file (TLV type 2), or apply the
# overrides of Samsung's bt_nvm_loading.xml to it.
#   bt-nvm.py dump <nvm>
#   bt-nvm.py apply <nvm> <bt_nvm_loading.xml> <out>
# Layout (btqca.h): TLV header (type:8, length:24), then tags of
# {tag_id:le16, tag_len:le16, reserve1:le32, reserve2:le32, data[tag_len]}.
import re, struct, sys
import xml.etree.ElementTree as ET


def parse(buf):
    tlv = struct.unpack_from('<I', buf, 0)[0]
    typ, length = tlv & 0xff, tlv >> 8
    if typ != 2:
        sys.exit(f'not an NVM TLV (type {typ})')
    tags, off, end = [], 4, 4 + length
    while off + 12 <= end:
        tid, tlen = struct.unpack_from('<HH', buf, off)
        tags.append((tid, off + 12, tlen))
        off += 12 + tlen
    return tags, length


def dump(path):
    buf = open(path, 'rb').read()
    tags, length = parse(buf)
    print(f'{path}: {len(buf)} bytes, TLV length {length}, {len(tags)} tags')
    for tid, doff, tlen in tags:
        print(f'  tag {tid:4d} len {tlen:4d}: {buf[doff:doff + min(tlen, 24)].hex(" ")}')


def apply(path, xml, out):
    buf = bytearray(open(path, 'rb').read())
    tags = {tid: (doff, tlen) for tid, doff, tlen in parse(buf)[0]}
    root = ET.parse(xml).getroot()
    for el in root:
        m = re.fullmatch(r'Tag(\d+)', el.tag)
        if not m:
            continue
        tid = int(m.group(1))
        if tid not in tags:
            sys.exit(f'tag {tid} not in the NVM')
        doff, tlen = tags[tid]
        kind = el.find('ChangeType').get('type')
        if int(el.find('Length').get('len')) != tlen:
            # written for another NVM layout: offsets would land elsewhere
            print(f'tag {tid}: SKIPPED, length {tlen} but the XML says '
                  f'{el.find("Length").get("len")}')
            continue
        before = bytes(buf[doff:doff + tlen])
        if kind == 'entire':
            vals = [int(v, 16) for v in re.findall(r'0x[0-9a-fA-F]+', el.find('Changes').text)]
            if len(vals) != tlen:
                sys.exit(f'tag {tid}: {len(vals)} values for {tlen} bytes')
            buf[doff:doff + tlen] = bytes(vals)
        else:
            offs = [int(o.get('value')) for o in el.find('Offset')]
            vals = [int(c.get('value'), 16) for c in el.find('Changes')]
            for o, v in zip(offs, vals):
                buf[doff + o] = v
        print(f'tag {tid} ({kind}):\n  was {before.hex(" ")}\n  now {bytes(buf[doff:doff + tlen]).hex(" ")}')
    open(out, 'wb').write(buf)


if __name__ == '__main__':
    if sys.argv[1] == 'dump':
        dump(sys.argv[2])
    else:
        apply(*sys.argv[2:5])
