#!/usr/bin/env python3
"""Emit a .def forwarding every hid.dll export to hid_orig, minus the two the
shim implements itself. Usage: gen_def.py <path to Wine's hid.dll>"""
import struct
import sys

IMPLEMENTED = {"HidP_GetUsageValue", "HidP_GetUsages"}


def exports(path):
    data = open(path, "rb").read()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    dir_off = opt + (112 if magic == 0x20B else 96)
    n_sections = struct.unpack_from("<H", data, pe + 6)[0]
    sec_off = opt + struct.unpack_from("<H", data, pe + 20)[0]
    sections = [struct.unpack_from("<III", data, sec_off + i * 40 + 12) for i in range(n_sections)]

    def to_offset(rva):
        for va, raw_size, raw_ptr in sections:
            if va <= rva < va + raw_size:
                return raw_ptr + (rva - va)
        raise ValueError(f"unmapped rva {rva:#x}")

    table = to_offset(struct.unpack_from("<II", data, dir_off)[0])
    count = struct.unpack_from("<I", data, table + 24)[0]
    names = to_offset(struct.unpack_from("<I", data, table + 32)[0])
    for i in range(count):
        at = to_offset(struct.unpack_from("<I", data, names + i * 4)[0])
        yield data[at:data.index(b"\0", at)].decode("ascii")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: gen_def.py <hid.dll>")
    print("EXPORTS")
    for name in exports(sys.argv[1]):
        print(name if name in IMPLEMENTED else f"{name} = hid_orig.{name}")


if __name__ == "__main__":
    main()
