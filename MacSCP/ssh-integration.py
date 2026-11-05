#!/usr/bin/env python3
"""Disposable loopback SSH integration; does not use the user's SSH configuration."""
import getpass, os, pathlib, socket, subprocess, tempfile, time
workspace = pathlib.Path(__file__).resolve().parent.parent
cache = workspace / 'build/module-cache'
binary = workspace / 'build/ssh-network-test'
sources = ['SFTP', 'RemoteFileClient', 'CommanderAppearance', 'CommanderChrome', 'AppMenu', 'Resume', 'FTPPublication', 'QueueJournal', 'TransferPolicy', 'FTPTransport', 'Sites', 'SSHOptions', 'Navigation', 'Askpass', 'SSHCredentialChannel', 'SSHConnection', 'SSHAuthenticationLog', 'Listing', 'Drag', 'FTPUploadSource', 'FTPDownloadTarget', 'TextTransfer', 'Transfer', 'TransferScheduler', 'RelayTransfer', 'RelayJournal', 'Checksum', 'Sync', 'SSHNetworkTest']
subprocess.run(['/usr/bin/clang', '-c', str(workspace/'MacSCP/FTPCurl.c'), '-o', str(workspace/'build/checks/FTPCurl.o')], check=True)
subprocess.run(['/usr/bin/swiftc', '-module-cache-path', str(cache), *[str(workspace/'MacSCP'/f'{name}.swift') for name in sources], str(workspace/'build/checks/FTPCurl.o'), '-lcurl', '-o', str(binary)], check=True)
if os.environ.get('MACSCP_SSH_COMPILE_ONLY') == '1':
    raise SystemExit(0)
servers = []
with tempfile.TemporaryDirectory(prefix='macscp-net-', dir='/tmp') as tmp:
    root = pathlib.Path(tmp)
    os.chmod(root, 0o700)
    def generate(name):
        path = root / name
        subprocess.run(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(path)], check=True)
        return path
    client = generate('client_key')
    encrypted = root/'encrypted_key'
    subprocess.run(['/usr/bin/ssh-keygen', '-q', '-t', 'ed25519', '-N', 'macscp-network-fixture', '-f', str(encrypted)], check=True)
    (root/'authorized_keys').write_bytes(client.with_suffix('.pub').read_bytes()+encrypted.with_suffix('.pub').read_bytes())
    os.chmod(root/'authorized_keys', 0o600)
    known = []
    try:
        for name in ['target', 'jump']:
            hostkey = generate(name+'_host')
            with socket.socket() as probe:
                probe.bind(('127.0.0.1', 0))
                port = probe.getsockname()[1]
            config = root/(name+'.conf')
            config.write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {hostkey}
PidFile {root/(name+'.pid')}
AuthorizedKeysFile {root/'authorized_keys'}
StrictModes no
UsePAM no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers {getpass.getuser()}
AllowTcpForwarding yes
PermitUserEnvironment no
UseDNS no
LogLevel ERROR
Subsystem sftp /usr/libexec/sftp-server
''')
            subprocess.run(['/usr/sbin/sshd', '-t', '-f', str(config)], check=True)
            log = open(root/(name+'.log'), 'wb')
            server = subprocess.Popen(['/usr/sbin/sshd', '-D', '-e', '-f', str(config)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=log)
            servers.append((server, log, port, name))
            deadline = time.monotonic()+5
            while time.monotonic() < deadline:
                if server.poll() is not None:
                    log.flush()
                    raise RuntimeError(f'{name} sshd stopped: '+(root/(name+'.log')).read_text())
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=0.2):
                        break
                except OSError:
                    time.sleep(0.02)
            else:
                raise RuntimeError('local sshd readiness timeout')
            pub = ' '.join(hostkey.with_suffix('.pub').read_text().split()[:2])
            known.append(f'[127.0.0.1]:{port} {pub}\n')
        (root/'known_hosts').write_text(''.join(known))
        (root/'client.conf').write_text(f'''Host *
 IdentityFile "{client}"
 IdentitiesOnly yes
 UserKnownHostsFile "{root/'known_hosts'}"
 GlobalKnownHostsFile /dev/null
 StrictHostKeyChecking yes
 BatchMode yes
 PasswordAuthentication no
 KbdInteractiveAuthentication no
 ConnectTimeout 5
''')
        (root/'client-encrypted.conf').write_text((root/'client.conf').read_text().replace(str(client), str(encrypted)).replace('BatchMode yes', 'BatchMode no'))
        helper = root/'fixture askpass'
        helper.write_text(f'''#!/bin/sh
[ "$1" = "--ssh-askpass" ] || exit 1
printf 'prompt\\n' >> "{root/'prompts'}"
if [ -f "{root/'cancel-mode'}" ]; then
 : > "$MACSCP_AUTH_CANCEL_FILE"
 exit 1
fi
printf '%s\\n' 'macscp-network-fixture'
''')
        helper.chmod(0o700)
        result = subprocess.run([str(binary), tmp, str(servers[0][2]), str(servers[1][2])], cwd=workspace, timeout=45)
        if result.returncode:
            for name in ['master.log', 'jump-master.log', 'target-master.log', 'target.log', 'jump.log']:
                path = root/name
                if path.exists():
                    print(name+': '+path.read_text()[-3000:])
            raise RuntimeError('SSH integration failed')
    finally:
        for server, log, _, _ in servers:
            if server.poll() is None:
                server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
            log.close()
