import json, os, socket, subprocess, sys, threading, time
from pathlib import Path
root=Path(__file__).resolve().parent.parent
exe=os.environ.get("XRAY_TEST_BIN")
bash=os.environ.get("BASH_TEST_BIN", "bash")
if not exe:
    print("SKIP: set XRAY_TEST_BIN to run Xray integration")
    sys.exit(0)
files=[root/'tests'/'tunnel-base.tmp.json',root/'tests'/'tunnel-generated.tmp.json']
server=client=None
udp=socket.socket(socket.AF_INET6,socket.SOCK_DGRAM); udp.bind(('::1',0)); target=udp.getsockname()[1]
tcp=socket.socket(socket.AF_INET6);tcp.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);tcp.bind(('::1',target));tcp.listen()
sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1];sock.close()
# A blackhole default verifies that the generated rule selects the dedicated freedom outbound.
files[0].write_text(json.dumps({'inbounds':[],'outbounds':[{'protocol':'blackhole','tag':'block'}]}),encoding='utf-8')
cmd='source <(sed \'/^case "${1:-}" in/,$d\' reality); CONFIG_FILE="$PWD/tests/tunnel-base.tmp.json"; tunnel_build_config "$1" ::1 "$2" tcp,udp > tests/tunnel-generated.tmp.json'
try:
    subprocess.run([bash,'-c',cmd,'_',str(port),str(target)],cwd=root,check=True)
    subprocess.run([exe,'-test','-config',str(files[1])],cwd=root,check=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    def tcp_echo():
        for _ in range(2):
            conn,_=tcp.accept()
            with conn: conn.sendall(conn.recv(128))
    def udp_echo():
        for _ in range(2):
            data,addr=udp.recvfrom(128);udp.sendto(data,addr)
    threading.Thread(target=tcp_echo,daemon=True).start();threading.Thread(target=udp_echo,daemon=True).start()
    server=subprocess.Popen([exe,'run','-config',str(files[1])],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    for _ in range(50):
        try: client=socket.create_connection(('127.0.0.1',port),timeout=0.2);break
        except OSError: time.sleep(0.1)
    if client is None: raise RuntimeError('Xray did not listen')
    client.settimeout(4);client.sendall(b'tcp-tunnel');assert client.recv(64)==b'tcp-tunnel';client.close();client=None
    client=socket.create_connection(('::1',port),timeout=4);client.settimeout(4);client.sendall(b'ipv6-tcp');assert client.recv(64)==b'ipv6-tcp';client.close();client=None
    for family,host in ((socket.AF_INET,'127.0.0.1'),(socket.AF_INET6,'::1')):
        with socket.socket(family,socket.SOCK_DGRAM) as u:
            u.settimeout(4);u.sendto(b'udp-tunnel',(host,port));assert u.recv(64)==b'udp-tunnel'
    print('Xray IPv4/IPv6 TCP + UDP to IPv6 target, isolated routing: PASS')
finally:
    if client: client.close()
    if server: server.terminate();server.wait(timeout=5)
    tcp.close();udp.close()
    for f in files: f.unlink(missing_ok=True)
