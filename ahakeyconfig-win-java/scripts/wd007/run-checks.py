import argparse, concurrent.futures, hashlib, json, subprocess, time
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('--java',required=True)
parser.add_argument('--output',required=True)
parser.add_argument('--filter',default='')
args=parser.parse_args()
output=Path(args.output).resolve();output.mkdir(parents=True,exist_ok=False)
classes=[
 'service.Wd007FirmwareMatrixChecks',
 'service.Wd007CursorRuntimeChecks',
 'service.Wd007CanvasReadbackChecks','service.Wd007ReadFailureChecks','service.Wd007TransferChecks',
 'service.Wd007HookManagementChecks','service.Wd007HookUiChecks',
 'service.connection.ManagedBridgeClientChecks','service.Wd007BehaviorChecks','service.Wd007SafetyChecks','service.Wd007RecoveryControllerChecks','service.Wd007UsbTerminationChecks','service.Wd007BridgeRetirementChecks','service.Wd007WindowExitChecks','service.KimiBridgeLifecycleCheck',
 'displayconfig.DisplayConfigChecks','displayconfig.DisplayConfigCapabilityChecks','displayconfig.DisplayConfigIsolationChecks',
 'displayconfig.DisplayConfigRaceChecks','displayconfig.DisplayConfigFxChecks','displayconfig.DisplayConfigRevision3Checks',
 'displayconfig.DisplayConfigRevision3UiChecks','displayconfig.DisplayConfigRound5Checks',
 'protocol.K1RouteProtocolChecks','packaging.K1RouteEditorChecks','packaging.Wd007DraftReadbackChecks','packaging.WindowCloseChecks',
 'firmware.DeviceMaintenanceChecks','firmware.BackupRestoreChecks','firmware.FirmwareUpdateChecks','firmware.SimpleFlashChecks',
 'update.UpdateCenterChecks','update.ReleaseSignatureChecks','service.SpeechLifecycleCheck']
if args.filter:classes=[c for c in classes if c.rsplit('.',1)[1] in args.filter.split(',')]
def run(name):
    log=output/(name.rsplit('.',1)[1]+'.log');home=output/(name.rsplit('.',1)[1]+'-home');home.mkdir()
    command=[args.java,'-Dfile.encoding=UTF-8','-Duser.home='+str(home),'-Dwd007.artifacts='+str(home/'artifacts'),'-cp','target/test-classes;target/classes;target/lib/*','com.example.ahakey.'+name]
    if name.endswith('DisplayConfigRevision3UiChecks'):command.append(str(output/'display-ui.png'))
    if name.endswith(('SimpleFlashChecks','ReleaseSignatureChecks')):command.append(str(output/(name.rsplit('.',1)[1]+'-artifacts')))
    started=time.monotonic()
    with log.open('wb') as stream:
        try:exit_code=subprocess.run(command,stdout=stream,stderr=subprocess.STDOUT,timeout=180).returncode
        except subprocess.TimeoutExpired:exit_code='TIMEOUT'
    result=dict(test=name,command=command,exit=exit_code,seconds=round(time.monotonic()-started,3),log=str(log),sha256=hashlib.sha256(log.read_bytes()).hexdigest())
    print(name,exit_code,flush=True);return result
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(run,classes))
(output/'RESULTS.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
raise SystemExit(0 if results and all(r['exit']==0 for r in results) else 1)
