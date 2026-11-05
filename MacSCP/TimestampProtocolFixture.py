#!/usr/bin/env python3
"""Owned stdio-only SFTP fixture: records metadata requests and rejects file payload I/O."""
import argparse,json,pathlib,struct,sys
p=argparse.ArgumentParser();p.add_argument('--audit',required=True);p.add_argument('--deny',action='store_true');p.add_argument('--missing-times',action='store_true');p.add_argument('--open-denied',action='store_true');p.add_argument('--link',action='store_true');args=p.parse_args()
audit=pathlib.Path(args.audit);events=[];accessed=1600000000;modified=1700000000
u32=lambda n:struct.pack('>I',n)
string=lambda value:u32(len(value))+value

def save():audit.write_text(json.dumps({'events':events,'accessed':accessed,'modified':modified}))
def read(n):
    data=sys.stdin.buffer.read(n)
    if len(data)!=n:raise EOFError()
    return data
def send(data):save();sys.stdout.buffer.write(u32(len(data))+data);sys.stdout.buffer.flush()
def status(sequence,code=0):send(bytes([101])+sequence+u32(code)+string(b'fixture status')+string(b''))
def attrs():
    flags=5 if args.missing_times else 13
    data=u32(flags)+struct.pack('>Q',4)+u32(0o120777 if args.link else 0o100600)
    return data if args.missing_times else data+u32(accessed)+u32(modified)
try:
    while True:
        size=struct.unpack('>I',read(4))[0]
        if size>1024*1024:raise ValueError('unexpected packet bound')
        packet=read(size);kind=packet[0];events.append(kind)
        if kind==1:send(bytes([2])+u32(3));continue
        sequence=packet[1:5];body=packet[5:]
        if kind==16:send(bytes([104])+sequence+u32(1)+string(b'/fixture')+string(b'/fixture')+u32(0))
        elif kind in (7,8):send(bytes([105])+sequence+attrs())
        elif kind==3:
            if args.open_denied:status(sequence,3)
            else:send(bytes([102])+sequence+string(b'owned-handle'))
        elif kind in (9,10):
            length=struct.unpack('>I',body[:4])[0];fields=body[4+length:]
            flags,atime,mtime=struct.unpack('>III',fields)
            if flags!=8:raise ValueError('unexpected metadata attributes')
            if args.deny:status(sequence,3)
            else:accessed=atime;modified=mtime;status(sequence)
        elif kind==4:status(sequence)
        else:status(sequence,4)
except EOFError:pass
