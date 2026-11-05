from pathlib import Path
import json,subprocess,hashlib,os,datetime
root=Path.cwd();out=root/'target/wd010-preview-build-02';app=root/'target/WD010-Preview-R3-LocalModel-1.0.21/image/AhaKeyStudio';derived=root/'target/WD010-Preview-Source-R3-1.0.21'
tests=out/'test-classes';tests.mkdir();jar=app/'app/ahakey-studio-1.0.0.jar';lib=app/'app/lib';runtime=app/'runtime/bin/java.exe';jdk=Path('D:/jdk-17.0.19.10-hotspot/bin/java.exe')
cp=';'.join([str(tests),str(jar),str(lib/'*')]);results=[]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
env=os.environ.copy();env['TEMP']=env['TMP']='D:/ahakey-wd010-preview-r3-20261105-temp'
sources=sorted((derived/'src/test/java').rglob('*.java'));arg=out/'package-test-sources.txt';arg.write_text('\n'.join('"'+p.as_posix()+'"' for p in sources),encoding='utf-8')
compilecmd=[str(jdk.with_name('javac.exe')),'-J-Dfile.encoding=UTF-8','-encoding','UTF-8','-cp',cp,'-d',str(tests),'@'+str(arg)]
with (out/'compile-packaged-tests.log').open('wb') as f:p=subprocess.run(compilecmd,stdout=f,stderr=subprocess.STDOUT,env=env)
write(out/'COMPILE_PACKAGED_TESTS.json',{'command':compilecmd,'cwd':str(root),'exit':p.returncode,'sources':len(sources),'source_hashes':{str(p.relative_to(derived)):sha(p) for p in sources}});assert p.returncode==0
modules=subprocess.run([str(runtime),'--list-modules'],capture_output=True,env=env);(out/'runtime-modules.log').write_bytes(modules.stdout+modules.stderr);assert modules.returncode==0
httpserver=b'jdk.httpserver@' in modules.stdout
manifest={'runtime':str(runtime),'product_jar':str(jar),'product_jar_sha256':sha(jar),'test_classes_only':str(tests),'no_implementation_classes':True,'product_has_jdk_httpserver':httpserver,'test_class_hashes':{str(p.relative_to(tests)):sha(p) for p in sorted(tests.rglob('*.class'))},'results':results}
write(out/'PACKAGED_RUNTIME_CHECKS.json',manifest)
suites=['wd010.RestorePreparationChecks','wd010.RestoreChecks','wd010.RestoreProductionUiChecks','wd010.RuntimeRestoreRaceChecks','firmware.DeviceMaintenanceChecks','displayconfig.DisplayConfigIsolationChecks','displayconfig.DisplayConfigRaceChecks','compatibility.FirmwareIdentityCompatibilityChecks','protocol.K1RouteProtocolChecks','firmware.BackupRestoreChecks','service.CursorWaitingChecks','wd009.HookManagementChecks','wd009.Wd009UiChecks','wd009.Wd009HookUiChecks','packaging.WindowCloseChecks','service.SpeechNativeCheck','service.QueuedDeliveryChecks','service.CloudTransactionUiChecks','service.CloudChecks','service.VoiceFinalChecks','service.CloudUiChecks']
for suite in suites:
 if (out/'STOP_AFTER_CURRENT').exists():break
 isCloud=suite in ['service.QueuedDeliveryChecks','service.CloudTransactionUiChecks','service.CloudChecks','service.VoiceFinalChecks','service.CloudUiChecks'];jvm=jdk if isCloud and not httpserver else runtime
 home=out/'homes'/('wd010-wd009-hook-r3-'+suite);home.mkdir(parents=True)
 tmp=Path(env['TEMP'])/suite;tmp.mkdir(exist_ok=True)
 cmd=[str(jvm),'-Dfile.encoding=UTF-8','-Duser.home='+str(home),'-Djava.io.tmpdir='+str(tmp),'-Dahakey.test.sourceRoot='+str(derived),'-cp',cp,'com.example.ahakey.wd010.CheckProcess','com.example.ahakey.'+suite]
 if suite=='wd010.RestoreProductionUiChecks':cmd+=[str(out/'packaged-ui')]
 if suite=='service.SpeechNativeCheck':
  wav=root/'target/wd006-dependencies/models/0.wav';assert sha(wav)=='7d93384ca14702cc584a7a33fe2fed92e89e708549161cb12ea38c916882103b'
  cmd += [str(app/'app/models'/n) for n in ['encoder.int8.onnx','decoder.int8.onnx','tokens.txt']]+[str(wav)]
 log=out/('packaged-'+suite+'.log');started=datetime.datetime.now(datetime.timezone.utc).isoformat()
 print('START',suite,flush=True)
 with log.open('wb') as stream:p=subprocess.run(cmd,stdout=stream,stderr=subprocess.STDOUT,cwd=out,env=env,creationflags=0x08000000)
 result={'suite':suite,'exit':p.returncode,'jvm_kind':'full_jdk_for_test_httpserver' if jvm==jdk else 'packaged_runtime','command':cmd,'cwd':str(out),'home':str(home),'temp':str(tmp),'started':started,'log':str(log.relative_to(root)),'log_sha256':sha(log)};results.append(result);write(out/'PACKAGED_RUNTIME_CHECKS.json',manifest)
 print('DONE',suite,p.returncode,flush=True)
 if p.returncode:break
assert len(results)==len(suites) and all(r['exit']==0 for r in results)
