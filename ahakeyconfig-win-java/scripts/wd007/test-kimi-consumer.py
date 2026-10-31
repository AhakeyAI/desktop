"""Replay the installed consumer's exact loader against Java's compatibility endpoint."""
import argparse, hashlib, socket, struct, subprocess
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('--java',required=True)
parser.add_argument('--consumer',required=True)
args=parser.parse_args()
source=Path(args.consumer).read_text(encoding='utf-8')
loader=source[source.index('def _load_ahakey_override_uncached('):source.index('\ndef get_ahakey_approval_override(')]
for state in ['auto','swapped-auto','custom','unknown','disconnected']:
    child=subprocess.Popen([args.java,'-cp','target/test-classes;target/classes;target/lib/*','com.example.ahakey.service.KimiBridgeLifecycleCheck','consumer-probe',state],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
    try:
        port=None
        for line in child.stdout:
            if line.startswith('KIMI_PROBE_PORT='):
                port=int(line.split('=')[1]);break
        assert port is not None,'Java probe failed'
        scope=dict(socket=socket,struct=struct,_AHAKEY_BRIDGE_HOST='127.0.0.1',_AHAKEY_BRIDGE_PORT=port)
        exec(loader,scope)
        result=scope['_load_ahakey_override_uncached']()
        if state in ['auto','swapped-auto']:assert result and result['is_auto'] is True,(state,result)
        else:assert result is None,(state,result)
        print('PASS actual Kimi consumer:',state,repr(result))
        child.communicate('\n',timeout=3)
        assert child.returncode==0
    finally:
        if child.poll() is None:child.kill();child.wait(timeout=2)
print('Consumer source SHA256:',hashlib.sha256(source.encode()).hexdigest())
