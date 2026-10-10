"""Inspect PE export names without loading/executing DLL code."""
import argparse
import json
from pathlib import Path
import struct

def exports(payload: bytes) -> list[str]:
    def u16(n): return struct.unpack_from('<H', payload, n)[0]
    def u32(n): return struct.unpack_from('<I', payload, n)[0]
    if payload[:2] != b'MZ': raise ValueError('not PE')
    pe = u32(0x3c)
    if payload[pe:pe+4] != b'PE\x00\x00': raise ValueError('missing PE signature')
    optional = pe + 24
    magic = u16(optional)
    if magic not in (0x10b, 0x20b): raise ValueError('unknown PE optional header')
    export_rva = u32(optional + (112 if magic == 0x20b else 96))
    if not export_rva: return []
    section_base = optional + u16(pe + 20)
    def raw(rva):
        for i in range(u16(pe + 6)):
            section = section_base + 40 * i
            virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from('<IIII', payload, section + 8)
            if virtual_address <= rva < virtual_address + max(virtual_size, raw_size):
                offset = raw_pointer + rva - virtual_address
                if offset >= len(payload): raise ValueError('RVA outside file')
                return offset
        raise ValueError('RVA outside sections')
    directory = raw(export_rva)
    count, name_rva = u32(directory + 24), u32(directory + 32)
    if count > 100000: raise ValueError('unbounded export count')
    names = raw(name_rva)
    found = []
    for index in range(count):
        offset = raw(u32(names + index * 4))
        end = payload.find(b'\x00', offset)
        if end < 0: raise ValueError('unterminated export name')
        found.append(payload[offset:end].decode('ascii'))
    return sorted(found)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dll', type=Path)
    args = parser.parse_args()
    print(json.dumps({'path': str(args.dll), 'exports': exports(args.dll.read_bytes()), 'dllLoaded': False}, sort_keys=True))
