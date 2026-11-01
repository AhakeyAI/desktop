"""Exercise only control-plane framing in our own compiled child; never enumerate/connect devices."""
import argparse, hashlib, json, os, socket, struct, subprocess, time, uuid
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('--bridge',required=True)
args=parser.parse_args()
exe=Path(args.bridge).resolve()
checks=0
def check(value,name):
    global checks
    assert value,name
    checks+=1
def packet(peer,body):
    raw=json.dumps(body).encode();peer.sendall(struct.pack('<BH',0x10,len(raw))+raw)
def receive(peer):
    def exact(n):
        data=b''
        while len(data)<n:
            chunk=peer.recv(n-len(data))
            if not chunk:raise EOFError()
            data+=chunk
        return data
    kind,length=struct.unpack('<BH',exact(3));check(kind==0x90,'response envelope')
    return json.loads(exact(length))
def launch(token,port):
    env=os.environ.copy();env['AHAKEY_BRIDGE_TOKEN']=token
    return subprocess.Popen([str(exe),'--studio','--minimized','--port',str(port)],env=env,cwd=exe.parent,
                            creationflags=subprocess.CREATE_NO_WINDOW,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
for scenario in ['normal','wrong-token','owner-closes','invalid-frame']:
    token=str(uuid.uuid4())
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1',0));port=reservation.getsockname()[1]
    child=launch(token,port)
    try:
        peer=None;end=time.monotonic()+4
        while peer is None and time.monotonic()<end:
            try:peer=socket.create_connection(('127.0.0.1',port),timeout=.15)
            except OSError:time.sleep(.025)
        check(peer is not None,'managed listener and window start without device enumeration')
        with peer:
            peer.settimeout(3)
            packet(peer,dict(version=1,requestId='1',op='hello',ownerToken=token if scenario!='wrong-token' else 'wrong',versions=[1]))
            if scenario=='wrong-token':
                check(peer.recv(1)==b'','unauthorized owner rejected')
            else:
                reply=receive(peer);check(reply['ok'] and 'session-writes' in reply['capabilities'],'versioned hello')
                instance=reply['bridgeInstanceId']
                if scenario=='normal':
                    check('visible-window' in reply['capabilities'],'compiled bridge advertises visible control surface')
                    packet(peer,dict(version=1,requestId='show',op='showWindow',bridgeInstanceId=instance))
                    check(receive(peer)['ok'],'show existing authenticated bridge window')
                    packet(peer,dict(version=1,requestId='status',op='studioStatus',bridgeInstanceId=instance,sequence=1,selectionAuthority='1:1:',message='离线 IPC 测试，无设备访问'))
                    check(receive(peer)['ok'],'coordinator status delivered to window')
                    packet(peer,dict(version=1,requestId='2',op='write',bridgeInstanceId=instance,sessionId='absent',targetId='fake',clientGeneration='1',channel='command',bytes='qrsAzN0='))
                    check(receive(peer)['code']=='SESSION_CHANGED','write without selected target rejected before GATT')
                    packet(peer,dict(version=1,requestId='2',op='write',bridgeInstanceId=instance))
                    check(receive(peer)['code']=='DUPLICATE_REQUEST','duplicate never replays')
                    packet(peer,dict(version=1,requestId='3',op='write',bridgeInstanceId='old'))
                    check(receive(peer)['code']=='INSTANCE_CHANGED','old instance fenced')
                    packet(peer,dict(version=1,requestId='4',op='shutdown',bridgeInstanceId=instance))
                    check(receive(peer)['revoked'],'shutdown revokes even without a device')
                elif scenario=='invalid-frame':
                    peer.sendall(bytes([0x10,0xff,0xff]));check(peer.recv(1)==b'','oversized frame rejected')
        check(child.wait(timeout=3)==0,'owned process terminates after owner closes or shutdown')
    finally:
        if child.poll() is None:child.kill();child.wait(timeout=2)
print(json.dumps(dict(status='PASS',checks=checks,bridge=str(exe),sha256=hashlib.sha256(exe.read_bytes()).hexdigest(),scope='private IPC only; no enumeration or GATT'),ensure_ascii=False))
