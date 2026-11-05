from pathlib import Path
import http.server,threading,json,subprocess,hashlib,os
r=Path.cwd();out=r/'target/wd010-preview-build-02';app=r/'target/WD010-Preview-R3-LocalModel-1.0.21/image/AhaKeyStudio';classes=out/'probe-classes';classes.mkdir();requests=[]
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):self.respond()
 def do_GET(self):self.respond()
 def respond(self):
  self.rfile.read(int(self.headers.get('Content-Length',0)));path=self.path.split('?')[0];requests.append(path)
  if path.endswith('/login'):data={'access_token':'probe-token'}
  elif path.endswith('/redeem'):data={}
  elif path.endswith('/native'):data={'out_trade_no':'probe-order','code_url':'weixin://wxpay/bizpayurl?pr=probe'}
  elif path.endswith('/order-status'):data={'status':'paid'}
  else:data={'user':{'phone':'probe-phone'},'policy':{'recharge_prices_fen':{'monthly':100}}}
  body=json.dumps({'code':0,'data':data}).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
cp=';'.join([str(classes),str(out/'test-classes'),str(app/'app/ahakey-studio-1.0.0.jar'),str(app/'app/lib/*')]);env=os.environ.copy();env['TEMP']=env['TMP']='D:/ahakey-wd010-preview-r3-20261105-temp'
compilecmd=['D:/jdk-17.0.19.10-hotspot/bin/javac.exe','-J-Dfile.encoding=UTF-8','-encoding','UTF-8','-cp',cp,'-d',str(classes),str(out/'PackagedCloudProbe.java')]
record={'fixture_sha256':sha(out/'PackagedCloudProbe.java'),'server_sha256':sha(Path(__file__)),'compile_command':compilecmd,'classpath_excludes_development_product_classes':True,'cwd':str(out)}
try:
 with (out/'compile-cloud-probe.log').open('wb') as f:p=subprocess.run(compilecmd,stdout=f,stderr=subprocess.STDOUT,env=env)
 record['compile_exit']=p.returncode;assert p.returncode==0
 home=out/'homes/wd010-cloud-probe';home.mkdir(parents=True);temp=Path(env['TEMP'])/'cloud-probe';temp.mkdir()
 cmd=[str(app/'runtime/bin/java.exe'),'-Dfile.encoding=UTF-8','-Duser.home='+str(home),'-Djava.io.tmpdir='+str(temp),'-cp',cp,'com.example.ahakey.wd010.CheckProcess','com.example.ahakey.service.PackagedCloudProbe','http://127.0.0.1:'+str(server.server_port)]
 record['command']=cmd
 with (out/'packaged-cloud-probe.log').open('wb') as f:p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,cwd=out,env=env,creationflags=0x08000000)
 record['exit']=p.returncode;record['log_sha256']=sha(out/'packaged-cloud-probe.log');assert p.returncode==0
 assert requests.count('/api/v1/auth/login')==1 and requests.count('/api/v1/coupon/redeem')==1 and requests.count('/api/v1/payment/wechat/native')==1
 print((out/'packaged-cloud-probe.log').read_text(encoding='utf-8',errors='replace').splitlines()[-1])
finally:
 server.shutdown();server.server_close();record['loopback_requests']=requests
 (out/'PACKAGED_CLOUD_PROBE.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
