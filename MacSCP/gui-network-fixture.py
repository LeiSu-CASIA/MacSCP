#!/usr/bin/env python3
"""Isolated real SSH fixture for visible acceptance. Stop via its stop marker."""
import getpass, json, os, pathlib, socket, subprocess, tempfile, time
workspace = pathlib.Path(__file__).resolve().parent.parent
root = pathlib.Path(tempfile.mkdtemp(prefix='macscp-gui-network-', dir='/tmp')).resolve()
os.chmod(root, 0o700)
server = None
try:
    def key(name, password=''):
        path = root/name
        subprocess.run(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', password, '-f', str(path)], check=True)
        return path
    host = key('host_key')
    identity = key('encrypted_key', 'macscp-gui-fixture')
    (root/'authorized_keys').write_bytes(identity.with_suffix('.pub').read_bytes())
    (root/'authorized_keys').chmod(0o600)
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    config = root/'sshd.conf'
    config.write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {host}
PidFile {root/'sshd.pid'}
AuthorizedKeysFile {root/'authorized_keys'}
StrictModes no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers {getpass.getuser()}
AllowTcpForwarding no
PermitUserEnvironment no
UseDNS no
LogLevel ERROR
Subsystem sftp /usr/libexec/sftp-server
''')
    subprocess.run(['/usr/sbin/sshd', '-t', '-f', str(config)], check=True)
    (root/'known_hosts').touch(mode=0o600)
    (root/'client.conf').write_text(f'''Host *
 IdentitiesOnly yes
 UserKnownHostsFile "{root/'known_hosts'}"
 GlobalKnownHostsFile /dev/null
 StrictHostKeyChecking ask
 BatchMode no
 PasswordAuthentication no
 KbdInteractiveAuthentication no
 ConnectTimeout 5
''')
    (root/'client.conf').chmod(0o600)
    for name in ['local/项目/数据', 'remote/远程目录/下一级', 'Finder接收']:
        (root/name).mkdir(parents=True)
    (root/'local/单个文件.txt').write_text('GUI upload fixture · 中文\n')
    (root/'remote/服务器文件.txt').write_text('GUI download fixture · 中文\n')
    (root/'remote/校验样本.bin').write_bytes(bytes(range(251))*8192)
    log = open(root/'sshd.log', 'wb')
    server = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(config)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=log)
    deadline = time.monotonic()+5
    while time.monotonic()<deadline:
        if server.poll() is not None:
            raise RuntimeError('GUI sshd exited: '+(root/'sshd.log').read_text())
        try:
            with socket.create_connection(('127.0.0.1',port),timeout=.2):
                break
        except OSError:
            time.sleep(.02)
    else:
        raise RuntimeError('GUI sshd readiness timeout')
    manifest = root/'fixture.json'
    manifest.write_text(json.dumps(dict(root=str(root),port=port,user=getpass.getuser(),key=str(identity),config=str(root/'client.conf'))))
    manifest.chmod(0o600)
    print('READY '+str(manifest), flush=True)
    subprocess.run(['/usr/bin/ssh-keygen','-lf',str(host.with_suffix('.pub'))], check=True)
    print('Stop marker: '+str(root/'stop'), flush=True)
    deadline=time.monotonic()+1800
    while not (root/'stop').exists() and time.monotonic()<deadline:
        if server.poll() is not None:
            raise RuntimeError('GUI sshd exited unexpectedly')
        time.sleep(.25)
finally:
    if server is not None:
        if server.poll() is None:
            server.terminate()
        try:
            server.wait(timeout=5)
        except subprocess.TimeoutExpired:
            server.kill();server.wait()
    # Keep evidence and generated files for verification; remove keys/config only.
    for name in ['host_key','encrypted_key','authorized_keys','client.conf','sshd.conf']:
        (root/name).unlink(missing_ok=True)
    print('STOPPED '+str(root), flush=True)
