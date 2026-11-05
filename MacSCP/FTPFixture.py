#!/usr/bin/env python3
"""Disposable loopback-only FTP/FTPS fixture. No user accounts/configuration involved."""
import argparse,datetime,json,os,pathlib,signal,socket,socketserver,ssl,stat,threading,time
p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--port-file',required=True);p.add_argument('--security',choices=['plain','explicit','implicit'],default='plain');p.add_argument('--mlsd-unsupported',action='store_true');p.add_argument('--mlsd-denied',action='store_true');p.add_argument('--mlsd-no-metadata',action='store_true');p.add_argument('--mlsd-no-permissions',action='store_true');p.add_argument('--mdtm-unsupported',action='store_true');p.add_argument('--mfmt-unsupported',action='store_true');p.add_argument('--fail-upload-once',action='store_true');p.add_argument('--deny-publish-once',action='store_true');p.add_argument('--auth-log');p.add_argument('--greeting-delay',type=float,default=0);p.add_argument('--size-delay',type=float,default=0);p.add_argument('--cert');p.add_argument('--key');args=p.parse_args()
root=pathlib.Path(args.root).resolve();context=None;fault_lock=threading.Lock();fault_used=False;publish_fault_used=False
if args.security!='plain':
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);context.minimum_version=ssl.TLSVersion.TLSv1_2;context.load_cert_chain(args.cert,args.key)
class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        global fault_used,publish_fault_used
        self.conn=self.request;self.cwd='/';self.passive=None;self.secure=args.security=='implicit';self.protect=False;self.authenticated=False;self.rename_source=None;self.restart=0
        try:
            if self.secure:self.conn=context.wrap_socket(self.conn,server_side=True)
            if args.greeting_delay:time.sleep(args.greeting_delay)
            self.reply('220 fixture ready')
            while True:
                line=bytearray()
                while not line.endswith(b'\r\n'):
                    b=self.conn.recv(1)
                    if not b:return
                    line+=b
                    if len(line)>8192:return
                text=line[:-2].decode('utf-8');command,_,value=text.partition(' ');command=command.upper()
                if command=='AUTH':
                    if args.auth_log:
                        with fault_lock:
                            with open(args.auth_log,'a') as log:log.write(value+'\n')
                    if context and not self.secure:self.reply('234 begin TLS');self.conn=context.wrap_socket(self.conn,server_side=True);self.secure=True
                    else:self.reply('502 TLS unavailable')
                elif command=='USER':self.reply('331 password required' if args.security=='plain' or self.secure else '534 TLS required')
                elif command=='PASS':
                    self.authenticated=value=='macscp-test-only' and (args.security=='plain' or self.secure);self.reply('230 logged in' if self.authenticated else '530 login failed')
                elif command=='QUIT':self.reply('221 goodbye');return
                elif not self.authenticated:self.reply('530 login required')
                elif command=='PWD':self.reply('257 "'+self.cwd+'"')
                elif command=='SYST':self.reply('215 UNIX Type: L8')
                elif command=='FEAT':self.conn.sendall(b'211-Features\r\n UTF8\r\n EPSV\r\n MLST type*;size*;modify*;UNIX.mode*;\r\n211 End\r\n')
                elif command in ['TYPE','OPTS','PBSZ']:self.reply('200 OK')
                elif command=='PROT':self.protect=value=='P';self.reply('200 protected' if self.protect else '534 protection required')
                elif command=='CWD':
                    path=self.path(value)
                    if path.is_dir():
                        relative=path.relative_to(root).as_posix();self.cwd='/' if relative=='.' else '/'+relative;self.reply('250 directory changed')
                    else:self.reply('550 no directory')
                elif command=='CDUP':self.cwd=str(pathlib.PurePosixPath(self.cwd).parent);self.reply('250 parent')
                elif command in ['EPSV','PASV']:
                    if self.passive:self.passive.close()
                    self.passive=socket.socket();self.passive.bind(('127.0.0.1',0));self.passive.listen(1);self.passive.settimeout(10);port=self.passive.getsockname()[1]
                    self.reply(f'229 Entering Extended Passive Mode (|||{port}|)' if command=='EPSV' else f'227 Entering Passive Mode (127,0,0,1,{port//256},{port%256})')
                elif command in ['MLSD','LIST','RETR','STOR','APPE']:
                    if command=='MLSD' and args.mlsd_denied:self.reply('550 MLSD permission denied');continue
                    if command=='MLSD' and args.mlsd_unsupported:self.reply('502 MLSD unavailable');continue
                    if args.security!='plain' and not self.protect:self.reply('534 encrypted data required');continue
                    path=self.path(value or self.cwd)
                    if command not in ['STOR','APPE'] and not path.exists():self.reply('550 missing');continue
                    if command in ['MLSD','LIST'] and not path.is_dir():self.reply('550 not directory');continue
                    if not self.passive:self.reply('425 passive required');continue
                    self.reply('150 data opening');data,_=self.passive.accept();self.passive.close();self.passive=None
                    if self.protect:data=context.wrap_socket(data,server_side=True)
                    try:
                        if command=='MLSD':
                            rows=['Type=cdir; .']
                            for child in sorted(path.iterdir()):
                                info=child.lstat();kind='dir' if stat.S_ISDIR(info.st_mode) else 'OS.unix=slink:'+os.readlink(child) if stat.S_ISLNK(info.st_mode) else 'file';stamp=datetime.datetime.fromtimestamp(info.st_mtime,datetime.timezone.utc).strftime('%Y%m%d%H%M%S')
                                details='' if args.mlsd_no_metadata else f'Size={info.st_size};Modify={stamp};'
                                permissions='' if args.mlsd_no_permissions else f'UNIX.mode={info.st_mode&0o7777:04o};'
                                rows.append(f'Type={kind};{details}{permissions} {child.name}')
                            data.sendall(('\r\n'.join(rows)+'\r\n').encode())
                        elif command=='LIST':
                            rows=[]
                            for child in sorted(path.iterdir()):
                                info=child.lstat();rows.append(f'{stat.filemode(info.st_mode)} 1 owner group {info.st_size} Nov 05 2026 {child.name}')
                            data.sendall(('\r\n'.join(rows)+'\r\n').encode())
                        elif command=='RETR':
                            with path.open('rb') as f:
                                f.seek(self.restart);self.restart=0
                                while True:
                                    chunk=f.read(4096)
                                    if not chunk:break
                                    data.sendall(chunk)
                                    if path.name=='slow.bin':time.sleep(.03)
                        else:
                            with fault_lock:
                                fail=args.fail_upload_once and command=='STOR' and not fault_used
                                if fail:fault_used=True
                            written=0
                            with path.open('ab' if command=='APPE' else 'wb') as f:
                                while True:
                                    chunk=data.recv(4096 if fail else 32768)
                                    if not chunk:break
                                    f.write(chunk);written+=len(chunk)
                                    if fail and written>=32768:break
                            if fail:
                                data.close();self.reply('451 injected temporary upload failure');continue
                        if isinstance(data,ssl.SSLSocket):
                            try:data.unwrap().close()
                            except (OSError,ssl.SSLError):pass
                    finally:data.close()
                    self.reply('226 transfer finished')
                elif command=='REST':
                    self.restart=int(value);self.reply('350 restart accepted')
                elif command=='MFMT':
                    if args.mfmt_unsupported:self.reply('502 MFMT unavailable');continue
                    stamp,_,filename=value.partition(' ');timestamp=datetime.datetime.strptime(stamp,'%Y%m%d%H%M%S').replace(tzinfo=datetime.timezone.utc).timestamp();os.utime(self.path(filename),(timestamp,timestamp));self.reply('213 modification time set')
                elif command=='SITE':
                    sub,_,rest=value.partition(' ');mode,_,filename=rest.partition(' ')
                    if sub.upper()=='CHMOD':os.chmod(self.path(filename),int(mode,8));self.reply('200 permissions set')
                    else:self.reply('502 unsupported SITE')
                elif command=='SIZE':
                    if args.size_delay:time.sleep(args.size_delay)
                    self.reply('213 '+str(self.path(value).stat().st_size))
                elif command=='MDTM':self.reply('502 MDTM unavailable' if args.mdtm_unsupported else '213 '+datetime.datetime.fromtimestamp(self.path(value).stat().st_mtime,datetime.timezone.utc).strftime('%Y%m%d%H%M%S'))
                elif command=='MKD':self.path(value).mkdir();self.reply('257 created')
                elif command=='DELE':self.path(value).unlink();self.reply('250 removed')
                elif command=='RMD':self.path(value).rmdir();self.reply('250 removed')
                elif command=='RNFR':self.rename_source=self.path(value);self.reply('350 rename destination required')
                elif command=='RNTO':
                    deny=False
                    with fault_lock:
                        if args.deny_publish_once and not publish_fault_used and '.macscp-resume-' in self.rename_source.name:
                            deny=True;publish_fault_used=True
                    if deny:self.rename_source=None;self.reply('550 injected publication denial')
                    else:self.rename_source.rename(self.path(value));self.rename_source=None;self.reply('250 renamed')
                else:self.reply('502 unsupported')
        except (OSError,ValueError,UnicodeError,ssl.SSLError):return
        finally:
            if self.passive:self.passive.close()
            self.conn.close()
    def path(self,value):
        raw=pathlib.PurePosixPath(value if value.startswith('/') else self.cwd+'/'+value)
        result=(root/str(raw).lstrip('/')).resolve()
        if result!=root and root not in result.parents:raise ValueError('outside fixture')
        return result
    def reply(self,text):self.conn.sendall((text+'\r\n').encode())
class Server(socketserver.ThreadingTCPServer):allow_reuse_address=True;daemon_threads=True
server=Server(('127.0.0.1',0),Handler);stop=threading.Event()
signal.signal(signal.SIGTERM,lambda *_:stop.set());signal.signal(signal.SIGINT,lambda *_:stop.set())
thread=threading.Thread(target=server.serve_forever,kwargs={'poll_interval':.05},daemon=True);thread.start()
parent=os.getppid()
def parent_watch():
    while not stop.wait(.25):
        if os.getppid()!=parent:stop.set();return
threading.Thread(target=parent_watch,daemon=True).start()
pathlib.Path(args.port_file).write_text(json.dumps({'port':server.server_address[1],'pid':os.getpid()}))
try:stop.wait()
finally:server.shutdown();server.server_close()
