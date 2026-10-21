import socket,json,time,argparse
p=argparse.ArgumentParser(description='Hardware regression: legacy state immediately followed by SINGLE/MULTI mode changes. Requires a connected test keyboard; writes runtime display state only, restores SINGLE afterward.')
p.add_argument('--gap',type=float,default=0,help='Diagnostic delay only; leave at zero for regression.')
p.add_argument('--rounds',type=int,default=8)
a=p.parse_args()
if not 1 <= a.rounds <= 20 or not 0 <= a.gap <= 1:p.error('rounds must be 1..20 and gap 0..1')
def rpc(obj):
 s=socket.socket(socket.AF_UNIX);s.settimeout(25);s.connect('/tmp/ahakey.sock');s.sendall((json.dumps(obj)+'\n').encode());b=b''
 while not b.endswith(b'\n'):
  c=s.recv(8192)
  if not c:break
  b+=c
 s.close();return json.loads(b) if b else {}
results=[]
try:
 for n in range(a.rounds):
  before=rpc({'cmd':'presentation_tasks'})
  if not before.get('connected'): print('DISCONNECTED',flush=True);break
  # Explicit SINGLE establishes the legacy state path before the trigger.
  if before.get('requestedMode')!=0:
   r=rpc({'cmd':'presentation_mode','mode':0})
   if r.get('requestedMode')!=0: print('SETUP_FAILED',r,flush=True);break
  rpc({'cmd':'state','value':7})
  if a.gap:time.sleep(a.gap)
  started=time.monotonic();r=rpc({'cmd':'presentation_mode','mode':1});elapsed=time.monotonic()-started
  item={'round':n,'gap':a.gap,'ok':r.get('requestedMode')==1,'seconds':round(elapsed,3),'reply':{k:v for k,v in r.items() if k!='tasks'}};results.append(item);print(json.dumps(item),flush=True)
  if not item['ok']:break
finally:
 try:
  current=rpc({'cmd':'presentation_tasks'})
  if current.get('connected') and current.get('requestedMode')==1:rpc({'cmd':'presentation_mode','mode':0})
 except Exception as e: print('RESTORE_ERROR',type(e).__name__,flush=True)
passed=len(results)==a.rounds and all(x['ok'] for x in results)
print('PASS' if passed else 'FAIL',flush=True)
raise SystemExit(0 if passed else 1)
