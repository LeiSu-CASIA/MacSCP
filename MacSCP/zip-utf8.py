#!/usr/bin/env python3
"""Mark ditto's existing UTF-8 names as UTF-8 without changing bundle payloads."""
import os
import pathlib
import struct
import sys
import zipfile

path = pathlib.Path(sys.argv[1])
data = bytearray(path.read_bytes())
with zipfile.ZipFile(path) as archive:
    position = archive.start_dir
    for item in archive.infolist():
        if data[position:position + 4] != b'PK\x01\x02':
            raise ValueError('Invalid central directory')
        name_length, extra_length, comment_length = struct.unpack_from('<3H', data, position + 28)
        name = bytes(data[position + 46:position + 46 + name_length])
        name.decode('utf-8', errors='strict')
        local = item.header_offset
        if data[local:local + 4] != b'PK\x03\x04':
            raise ValueError('Invalid local header')
        local_length = struct.unpack_from('<H', data, local + 26)[0]
        if bytes(data[local + 30:local + 30 + local_length]) != name:
            raise ValueError('Inconsistent ZIP filenames')
        for offset in (position + 8, local + 6):
            flags = struct.unpack_from('<H', data, offset)[0]
            struct.pack_into('<H', data, offset, flags | 0x800)
        position += 46 + name_length + extra_length + comment_length
temporary = path.with_suffix(path.suffix + '.utf8.tmp')
try:
    temporary.write_bytes(data)
    temporary.chmod(path.stat().st_mode & 0o7777)
    with zipfile.ZipFile(temporary) as archive:
        if archive.testzip() is not None:
            raise ValueError('ZIP payload verification failed')
    os.replace(temporary, path)
finally:
    temporary.unlink(missing_ok=True)
