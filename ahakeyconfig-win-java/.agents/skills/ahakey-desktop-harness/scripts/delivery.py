"""AhaKey delivery profiles / truthful Owner briefs / Owner-dispatched release batches.
Stdlib only; never executes a build, installer, product, model, device, Git write
or reference-workspace write. Records and hashes are NOT proof of execution or identity.
Existing v0.4 candidate/approval/build/packet records are immutable inputs here.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
from pathlib import Path
import zipfile
import guardrails as g
import firmware_intake as fwintake

H = '.ahakey-desktop-harness'
POLICY = H + '/delivery/POLICY.json'
BID = re.compile(r'WB-[0-9]{3,6}\Z')
VARIANTS = ('lite-no-local-model', 'model-bundled')
FORMS = ('jar_classpath', 'app_image', 'installer_exe', 'installer_msi')
SIDE = ('DELIVERY_PROFILE.json','ACCEPTANCE_COVERAGE.json','OWNER_BRIEF_INPUT.json',
        'FORMAL_FIRMWARE_GATE.json','DELIVERY_PACKET.json','OWNER_BRIEF.md','OWNER_RESULTS.json')


def enabled(h, root):
    return h.child(root, POLICY).exists()


def policy(h, root):
    x=h.read_json(h.child(root,POLICY))
    if x.get('schema_version')!=1 or x.get('install_relationship')!='exclusive_switchable':
        g.fail(h,'Invalid delivery policy; use reviewed upgrade, not manual rule replacement')
    return x


def write_new(h, p, obj):
    if p.exists():g.fail(h,'Record already exists; preserve history before an explicit revision: '+str(p))
    h.write_json(p,obj)


def asset(h,root,path):
    r=h.safe_rel(path).as_posix()
    return {'path':r,'sha256':h.ev_hash(root,r)}


def check_asset(h,root,x,label='evidence'):
    if not isinstance(x,dict) or x.get('sha256')!=h.ev_hash(root,x.get('path')):
        g.fail(h,'Changed/missing '+label)
    return x


def nonempty(h,x,label,minlen=4):
    return g.text(h,x,label,minlen)


def retained(h,root,c,event):
    """Append-only copies of supplementary records; does not overwrite old packets."""
    folder=h.cp(root,c['id'],'delivery-history/'+g.uid()+'-'+event)
    files={}
    for name in SIDE:
        p=h.cp(root,c['id'],name)
        if p.is_file():
            b=p.read_bytes();h.atomic(folder/name,b);files[name]=h.digest(b)
    h.write_json(folder/'MANIFEST.json',{'id':c['id'],'event':event,'at':h.now(),'files':files})
    return folder


def select_jar(h, b, supplied=None):
    names=[r for r in b['files'] if r.lower().endswith('.jar') and '/lib/' not in r.replace('\\','/')]
    if supplied:
        supplied=h.safe_rel(supplied).as_posix()
        if supplied not in b['files']:g.fail(h,'Primary artifact is not in the recorded build')
        return supplied
    roots=[x for x in names if '/original-' not in x and x.rsplit('/',1)[-1].startswith('ahakey-studio-')]
    choices=roots or names
    if len(choices)!=1:g.fail(h,'Primary JAR ambiguous; explicitly supply --artifact from BUILD_RECEIPT')
    return choices[0]


def observe_jar(h,root,b,primary):
    """Inspect bytes only. Classifies current JAR configuration, not EXE readiness."""
    p=h.child(root,primary)
    try:
        with zipfile.ZipFile(p) as z:
            names=z.namelist()
            if len(names)!=len(set(names)):g.fail(h,'Ambiguous JAR duplicate entries')
            cfgs=[n for n in names if n=='model_config.properties' or n=='BOOT-INF/classes/model_config.properties']
            if len(cfgs)>1:g.fail(h,'Ambiguous model configuration in JAR')
            cfg=z.read(cfgs[0]) if cfgs else b''
            if len(cfg)>1024*1024:g.fail(h,'Model config unexpectedly large')
            content=cfg.decode('utf-8-sig')
            matches=re.findall(r'^\s*model\.enabled\s*[:=]\s*(true|false)\s*$',content,re.M|re.I)
            if len(matches)>1:g.fail(h,'Duplicate model.enabled; DLA inspect effective Java properties semantics')
            default=None;src='src/main/java/com/example/ahakey/config/ModelConfig.java';src_rec=None
            sp=h.child(root,src)
            if sp.is_file():
                txt=sp.read_text(encoding='utf-8-sig')
                m=re.search(r'DEFAULT_MODEL_ENABLED\s*=\s*(true|false)\s*;',txt)
                if m:default=m.group(1)=='true';src_rec=asset(h,root,src)
            model=(matches[-1].lower()=='true') if matches else default
            weights=[n for n in names if n.startswith('models/') and not n.endswith('/')]
            manifest=z.read('META-INF/MANIFEST.MF').decode('utf-8','replace') if 'META-INF/MANIFEST.MF' in names else ''
    except (zipfile.BadZipFile,UnicodeError,KeyError) as e:g.fail(h,'Cannot inspect actual JAR: '+str(e))
    external_models={r:sha for r,sha in b['files'].items() if '/models/' in r.replace('\\','/')}
    return {'kind':'shared-source','model_enabled':model,
            'configuration_entry':cfgs[0] if cfgs else None,'configuration_sha256':h.digest(cfg),
            'configuration_text':content,'default_source':src_rec,
            'embedded_model_files':weights,'external_model_files':external_models,
            'onnx_dependencies':[r for r in b['files'] if 'onnxruntime' in r.lower() and r.endswith('.jar')],
            'manifest_text':manifest,
            'classification':'shared JAR / local model disabled' if model is False else ('shared JAR / local model enabled; model readiness unverified' if model else 'shared JAR / model configuration UNKNOWN'),
            'limits':'Byte/source observation only. Not light installer, model installer, model-load or runtime PASS.'}


def profile_create(h,root,c,primary=None):
    b=g.build_ok(h,root,c)
    if b.get('runtime_kind')!='jar_classpath':g.fail(h,'Auto-adopt currently supports actual JAR builds. For other forms use a reviewed profile with bound build metadata.')
    primary=select_jar(h,b,primary)
    r={'schema_version':1,'id':c['id'],'created_at':h.now(),
       'build_receipt':asset(h,root,H+'/changes/'+c['id']+'/BUILD_RECEIPT.json'),
       'code_fingerprint':b['code_fingerprint'],'build_round':c['build_round'],
       'delivery_form':'jar_classpath','product_variant':'shared-source',
       'primary':asset(h,root,primary),'observation':observe_jar(h,root,b,primary),
       'entrypoint':b['entrypoint'],'runtime_roots':b['artifact_roots'],
       'claim_scope':'This exact JAR/configuration only; both installer variants NOT tested.'}
    return r


def profile_ok(h,root,c):
    x=h.read_json(h.cp(root,c['id'],'DELIVERY_PROFILE.json'));b=g.build_ok(h,root,c)
    check_asset(h,root,x.get('build_receipt'),'profile build receipt')
    if x.get('id')!=c['id'] or x.get('code_fingerprint')!=b['code_fingerprint'] or x.get('build_round')!=c['build_round']:g.fail(h,'Delivery profile stale')
    if x.get('delivery_form') not in FORMS:g.fail(h,'Declare delivery form separately from product variant')
    check_asset(h,root,x.get('primary'),'primary artifact')
    if x['primary']['path'] not in b['files']:g.fail(h,'Primary absent from build manifest')
    if x['delivery_form']=='jar_classpath':
        obs=observe_jar(h,root,b,x['primary']['path'])
        if x.get('product_variant')!='shared-source' or x.get('observation')!=obs:g.fail(h,'JAR observation/configuration changed or misclassified as installer')
        if obs['model_enabled'] is None:g.fail(h,'Effective local-model configuration unknown; DLA inspect actual default before publishing')
    return x


def acceptance_items(h, root, c):
    """Exact source excerpts, not a generated replacement for approved requirements."""
    path=h.cp(root,c['id'],'CONTRACT.md');lines=path.read_text(encoding='utf-8-sig').splitlines()
    selected=False;heading='';rows=[]
    for i,line in enumerate(lines,1):
        if re.match(r'^##\s+',line):
            heading=line.strip();selected=bool(re.search(r'验收|[Aa]cceptance|[Vv]erification',heading))
        if selected and re.match(r'^\s*[-*]\s+\S',line):
            rows.append({'id':'A%03d'%(len(rows)+1),'line':i,'section':heading,'source_text':line.strip()})
    if not rows:g.fail(h,'No explicit acceptance bullets found in Contract; DLA must establish an explicit acceptance mapping without rewriting an approved Contract. Do not infer PASS.')
    return {'contract_sha256':h.digest(path.read_bytes()),'items':rows}


def init_delivery(h,root,c,primary=None):
    g.changes(h,root,c);b=g.build_ok(h,root,c)
    idx=acceptance_items(h,root,c)
    pending={}
    p=h.cp(root,c['id'],'DELIVERY_PROFILE.json')
    if not p.exists():pending[p]=profile_create(h,root,c,primary)
    q=h.cp(root,c['id'],'OWNER_BRIEF_INPUT.json')
    existing=h.read_json(h.cp(root,c['id'],'OWNER_TEST.json')) if h.cp(root,c['id'],'OWNER_TEST.json').exists() else {}
    seed_path=h.child(root,H+'/delivery/WD001_BRIEF_SEED.json')
    seed=h.read_json(seed_path) if seed_path.exists() else {}
    seeded=(c['id']=='WD-001' and seed.get('contract_sha256')==idx['contract_sha256'])
    if not q.exists():
        if seeded:brief=seed['brief']
        else:
            brief={'schema_version':1,'id':c['id'],'reviewed_by_dla':False,'review_note':'',
               'test_goal':c['title'],'ui_entry':'', 'java_executable':'',
               'connection':existing.get('connection',''),'preconditions':existing.get('preconditions',''),
               'recovery':existing.get('recovery',''),'result_return':existing.get('result_return',''),
               'deliberately_unchanged':existing.get('deliberately_unchanged',''),
               'steps':[{'id':'T%02d'%(i+1),'group':'功能联调','action':x['action'],'expected':x['expected'],
                         'device_step':bool(c['requirements']['device_related'])} for i,x in enumerate(existing.get('steps',[]))]}
        pending[q]=brief
    cp=h.cp(root,c['id'],'ACCEPTANCE_COVERAGE.json')
    if not cp.exists():
        rows=[]
        for r in idx['items']:
            item={**r,'disposition':'pending','step_ids':[],'evidence':[],'reason':'','owner_exception':None}
            if seeded and r['id'] in seed.get('mapping',{}):item.update(seed['mapping'][r['id']])
            rows.append(item)
        pending[cp]={'schema_version':1,'id':c['id'],'contract_sha256':idx['contract_sha256'],
             'reviewed_by_dla':False,'review_note':'','rows':rows,
             'meaning':'Mapping draft. Original Contract unchanged. No test results are inferred.'}
    for path,value in pending.items():write_new(h,path,value)
    print('DELIVERY DRAFTS READY:',c['id'],'; no old task/build/packet/approval overwritten.')
    print('DLA must complete mapping/review note, verify formal Firmware gate, then preview/publish. No test performed.')


def brief_input_ok(h,root,c):
    x=h.read_json(h.cp(root,c['id'],'OWNER_BRIEF_INPUT.json'))
    if x.get('id')!=c['id'] or x.get('reviewed_by_dla') is not True:g.fail(h,'DLA must inspect the draft Owner brief against actual Contract and UI; no automatic endorsement')
    for k in ('test_goal','ui_entry','connection','preconditions','recovery','result_return','deliberately_unchanged','review_note'):nonempty(h,x.get(k),'brief.'+k)
    pro=h.read_json(h.cp(root,c['id'],'DELIVERY_PROFILE.json'))
    if pro.get('delivery_form')=='jar_classpath':
        java=x.get('java_executable','')
        if not isinstance(java,str) or not Path(java).is_absolute() or not Path(java).is_file():g.fail(h,'Specify and verify the actual absolute Java executable before publishing; no Java installation is performed')
        nonempty(h,x.get('launch_instructions'),'verified launch recipe')
    steps=x.get('steps')
    if not isinstance(steps,list) or not steps:g.fail(h,'Human-readable action/expected steps are required, not only document links')
    ids=set()
    for s in steps:
        sid=s.get('id')
        if not isinstance(sid,str) or not re.fullmatch(r'T[0-9]{2,4}',sid) or sid in ids:g.fail(h,'Step IDs must be unique T01 etc')
        ids.add(sid)
        for k in ('group','action','expected'):nonempty(h,s.get(k),'step.'+k)
        if type(s.get('device_step')) is not bool:g.fail(h,'Mark device vs non-device steps')
    return x


def evidence_ok(h,root,x):
    workspace=x.get('workspace')
    base=root if workspace=='windows' else h.external_root(root,workspace)
    check_asset(h,base,x,'acceptance evidence')
    nonempty(h,x.get('scope'),'evidence coverage');nonempty(h,x.get('explanation'),'evidence applicability')
    if x.get('result')!='pass' or x.get('kind') not in ('machine','static','real_device','owner_uat'):g.fail(h,'Reused evidence must identify actual result and method; record presence is not PASS')


def coverage_ok(h,root,c):
    cov=h.read_json(h.cp(root,c['id'],'ACCEPTANCE_COVERAGE.json'));idx=acceptance_items(h,root,c);brief=brief_input_ok(h,root,c)
    if cov.get('id')!=c['id'] or cov.get('contract_sha256')!=idx['contract_sha256']:g.fail(h,'Acceptance mapping bound to a different Contract')
    if cov.get('reviewed_by_dla') is not True: g.fail(h,'DLA acceptance mapping review still pending')
    nonempty(h,cov.get('review_note'),'acceptance mapping review')
    rows=cov.get('rows',[])
    if len(rows)!=len(idx['items']) or {x.get('id') for x in rows}!={x['id'] for x in idx['items']}:g.fail(h,'Every approved acceptance item must be mapped exactly once; do not remove required tests')
    expected={x['id']:x for x in idx['items']};ids={s['id'] for s in brief['steps']}
    for row in rows:
        orig=expected[row['id']]
        if any(row.get(k)!=orig[k] for k in ('line','section','source_text')):g.fail(h,'Acceptance source text/line altered: '+row['id'])
        mode=row.get('disposition');nonempty(h,row.get('reason'),'mapping rationale '+row['id'])
        if mode=='planned_owner':
            linked=row.get('step_ids')
            if not linked or len(linked)!=len(set(linked)) or not set(linked).issubset(ids):g.fail(h,'Acceptance item lacks executable Owner steps: '+row['id'])
        elif mode=='existing_evidence':
            if not row.get('evidence'):g.fail(h,'Reused acceptance evidence missing: '+row['id'])
            for x in row['evidence']:evidence_ok(h,root,x)
        elif mode=='owner_deferred':
            ex=row.get('owner_exception')
            check_asset(h,root,ex,'explicit Owner acceptance exception')
            if ex.get('item_id')!=row['id']:g.fail(h,'Exception must name this acceptance item')
            quote=nonempty(h,ex.get('quote'),'Owner actual words');nonempty(h,ex.get('scope'),'exception scope')
            if quote not in h.child(root,ex['path']).read_text(encoding='utf-8-sig'):g.fail(h,'Exception quote absent from Owner source; cannot infer waiver')
        else:g.fail(h,'Unresolved acceptance item: '+row['id'])
    return cov


def formal_gate_validate(h,fw,gate_rel,identity):
    p=h.child(fw,gate_rel);gate=h.read_json(p)
    # Explicit adapter for observed firmware schema. Unknown schemas must not be guessed.
    if gate.get('schema_version')!=6 or gate.get('result')!='PASS' or not gate.get('candidate_commit') or not gate.get('checkpoint'):
        g.fail(h,'Not a supported formal Firmware PASS gate (schema 6); READY_FOR_REGATE/build-only does not qualify')
    if gate.get('contract_errors') or gate.get('path_errors') or not isinstance(gate.get('machine_checks'),list) or not gate['machine_checks']:
        g.fail(h,'Formal Firmware gate has errors or no machine checks')
    if any(x.get('pass') is not True or (x.get('returncode') not in (None,0)) for x in gate['machine_checks']):g.fail(h,'Firmware machine checks not all passing')
    dirty=gate.get('dirty_scope',{})
    if dirty.get('candidate_blocking') or dirty.get('unknown'):g.fail(h,'Formal gate retains candidate blockers')
    a=identity['artifact'];ga=gate.get('artifact',{})
    if h.safe_rel(ga.get('path')).as_posix()!=h.safe_rel(a['path']).as_posix() or ga.get('sha256','').lower()!=a['sha256'].lower() or ga.get('exists') is not True or ga.get('sha256_match') is not True:
        g.fail(h,'Formal gate artifact is not the exact Firmware paired with this task')
    if h.ev_hash(fw,a['path'])!=a['sha256'].lower():g.fail(h,'Actual Firmware artifact bytes changed')
    candidate=gate['candidate_commit']
    if candidate not in identity.get('firmware_version','') and candidate not in identity.get('candidate_id',''):
        g.fail(h,'Formal gate candidate commit not in the preserved Firmware identity; DLA reconcile, no guessed pairing')
    return gate


def formal_gate_bind(h,root,c,gate_rel):
    ident=h.read_json(h.cp(root,c['id'],'FIRMWARE_IDENTITY.json'));fw=h.external_root(root,'firmware')
    gate_rel=h.safe_rel(gate_rel).as_posix();gate=formal_gate_validate(h,fw,gate_rel,ident)
    record={'schema_version':1,'id':c['id'],'observed_at':h.now(),
        'firmware_identity':asset(h,root,H+'/changes/'+c['id']+'/FIRMWARE_IDENTITY.json'),
        'formal_gate':asset(h,fw,gate_rel),'adapter':'firmware_gate_schema6',
        'artifact':ident['artifact'],'candidate_commit':gate['candidate_commit'],'checkpoint':gate['checkpoint'],
        'producer':'Firmware Harness; Windows read-only reference',
        'installed_device_status':'requires_owner_confirmation',
        'limits':'Formal eligibility/file identity only; does not prove physical device flashed or UAT passed.'}
    retained(h,root,c,'before-formal-gate');h.write_json(h.cp(root,c['id'],'FORMAL_FIRMWARE_GATE.json'),record)
    print('FORMAL FIRMWARE GATE BOUND:',gate_rel,'; original identity/packet retained, device flashing NOT asserted.')


def formal_gate_ok(h,root,c):
    if not c['requirements']['device_related']:return None
    x=h.read_json(h.cp(root,c['id'],'FORMAL_FIRMWARE_GATE.json'))
    check_asset(h,root,x.get('firmware_identity'),'preserved Firmware identity')
    fw=h.external_root(root,'firmware');check_asset(h,fw,x.get('formal_gate'),'formal Firmware gate')
    ident=h.read_json(h.child(root,x['firmware_identity']['path']))
    gate=formal_gate_validate(h,fw,x['formal_gate']['path'],ident)
    if x.get('id')!=c['id'] or x.get('candidate_commit')!=gate['candidate_commit'] or x.get('artifact')!=ident['artifact']:g.fail(h,'Formal gate supplement inconsistent')
    return x


def all_inputs(h,root,c):
    profile=profile_ok(h,root,c);brief=brief_input_ok(h,root,c);cov=coverage_ok(h,root,c);fw=formal_gate_ok(h,root,c)
    return profile,brief,cov,fw


def render_brief(h,root,c,ready):
    """Same structured inputs drive the file and stdout; no independent chat-only facts."""
    pro=h.read_json(h.cp(root,c['id'],'DELIVERY_PROFILE.json'));bf=h.read_json(h.cp(root,c['id'],'OWNER_BRIEF_INPUT.json'))
    pth=h.child(root,pro['primary']['path']);form=pro['delivery_form']
    headline='交测条件核对完成；设备步骤仍须先确认实机身份' if ready else '预览／待补证据：不是新的测试授权'
    lines=[f'# {c["id"]} Owner 测试简报',f'**{headline}**',
           '\n## 这次测什么',bf.get('test_goal',''),f'入口：{bf.get("ui_entry","")}',
           f'交付形式：{form}；产品发行版：{pro.get("product_variant")}',
           'JAR 结果只覆盖这份 JAR/config；不代表轻量EXE、带模型EXE、安装切换或发布通过。',
           '\n## Windows 文件与启动',f'工作目录：`{root}`',f'主产物：`{pth}`',f'SHA256：`{pro["primary"]["sha256"]}`',
           f'实际模型配置：{pro.get("observation",{}).get("classification","见绑定配方")}',
           '配套输入／运行依赖：'+', '.join('`'+str(h.child(root,p))+'`' for p in pro.get('runtime_roots',[])),
           '产物存在与打包成功不代表已经启动成功。']
    if form=='jar_classpath':
        lines+=['本次直接运行 JAR，不安装新版 EXE。','启动方式（DLA核对后的实际配方，不由Harness猜测）：','```powershell',bf.get('launch_instructions',''),'```']
    else:lines+=['启动／安装步骤：'+bf.get('launch_instructions','见批准配方；不可由后缀推断')]
    if c['requirements']['device_related']:
        identity=h.read_json(h.cp(root,c['id'],'FIRMWARE_IDENTITY.json'));fwroot=h.external_root(root,'firmware')
        lines+=['\n## Firmware 原件（只读引用）','来源：Firmware Harness 已有候选；Windows 不生成 HEX、不自动烧录。',
           f'硬件：{identity["hardware_model"]}',f'固件说明：{identity["firmware_version"]}',
           f'HEX 完整路径：`{h.child(fwroot,identity["artifact"]["path"])}`',
           f'SHA256：`{identity["artifact"]["sha256"]}`']
        gatep=h.cp(root,c['id'],'FORMAL_FIRMWARE_GATE.json')
        if gatep.exists():
            gate=h.read_json(gatep);lines += [f'正式Gate：`{h.child(fwroot,gate["formal_gate"]["path"])}`',f'候选提交：`{gate["candidate_commit"]}`']
        else:lines+=['正式Gate引用：待核对，旧的READY_FOR_REGATE不能代替。']
        lines+=['物理设备是否已刷此HEX：必须由Owner确认，文件hash不能证明已烧入。']
    lines+=['\n## 前置条件',bf.get('preconditions',''), '连接方式：'+bf.get('connection',''),
            '\n## 操作与预期']
    for s in bf.get('steps',[]):
        lines += [f'### {s["id"]} · {s["group"]}',s['action'],'**预期：** '+s['expected'],
                  '结果填写：通过／失败／未执行。'+('设备步骤：确认硬件/固件后再执行。' if s.get('device_step') else '')]
    covp=h.cp(root,c['id'],'ACCEPTANCE_COVERAGE.json')
    if covp.exists():
        cov=h.read_json(covp);lines+=['\n## 合同验收覆盖（不是执行结果）']
        for r in cov['rows']:lines += [f'- {r["id"]}：{r["source_text"]} → {r["disposition"]}；'+(','.join(r.get('step_ids',[])) or r.get('reason',''))]
    lines+=['\n## 停止与恢复',bf.get('recovery',''),'\n## 本轮不代表什么',bf.get('deliberately_unchanged',''),
            '\n## 你怎样反馈',bf.get('result_return',''),
            '\n本轮Agent已经做过的机器检查见构建/审阅回执；本简报生成没有启动程序、访问设备或执行测试。',
            'Owner UAT：尚待真实反馈。Git、安装切换和发布权限不因生成简报而扩大。']
    return '\n\n'.join(lines)+'\n'


def publish(h,root,c):
    all_inputs(h,root,c);g.delivery_ok(h,root,c);h.packet_ok(root,c)
    retained(h,root,c,'before-handoff')
    text=render_brief(h,root,c,True);h.atomic(h.cp(root,c['id'],'OWNER_BRIEF.md'),text.encode())
    names=['DELIVERY_PROFILE.json','OWNER_BRIEF_INPUT.json','ACCEPTANCE_COVERAGE.json','OWNER_BRIEF.md']
    if c['requirements']['device_related']:names+=['FORMAL_FIRMWARE_GATE.json']
    rec={'schema_version':1,'id':c['id'],'at':h.now(),'build_round':c['build_round'],
         'scope':'exact_current_form_internal_integration_not_release',
         'legacy_packet':asset(h,root,H+'/changes/'+c['id']+'/test_packet.json'),
         'supplements':{n:h.ev_hash(root,H+'/changes/'+c['id']+'/'+n) for n in names},
         'source_fingerprint':g.fp(h,root)['sha256'],'tests_executed_by_publish':False}
    h.write_json(h.cp(root,c['id'],'DELIVERY_PACKET.json'),rec)
    s=h.state(root);s.update(mode='OWNER_TEST',next_actor='Owner',next_mode='REAL_TEST')
    s['owner_action']={'required':True,'action':'按已直接输出的OWNER_BRIEF逐步测试；先确认设备固件；可用自然语言和截图反馈。'}
    s['test_action']={'required':True,'brief':H+'/changes/'+c['id']+'/OWNER_BRIEF.md','packet':H+'/changes/'+c['id']+'/DELIVERY_PACKET.json',
                      'meaning':'eligible to execute planned steps; not actual UAT PASS'}
    h.save_state(root,s);print(text)
    return rec


def delivery_packet_ok(h,root,c):
    g.delivery_ok(h,root,c);h.packet_ok(root,c);all_inputs(h,root,c)
    p=h.read_json(h.cp(root,c['id'],'DELIVERY_PACKET.json'))
    check_asset(h,root,p.get('legacy_packet'),'base test packet')
    if p.get('id')!=c['id'] or p.get('build_round')!=c['build_round'] or p.get('source_fingerprint')!=g.fp(h,root)['sha256']:g.fail(h,'Supplemental handoff stale')
    required={'DELIVERY_PROFILE.json','OWNER_BRIEF_INPUT.json','ACCEPTANCE_COVERAGE.json','OWNER_BRIEF.md'}
    if c['requirements']['device_related']:required.add('FORMAL_FIRMWARE_GATE.json')
    if set(p.get('supplements',{}))!=required:g.fail(h,'Handoff supplements incomplete')
    for n,sha in p['supplements'].items():
        if sha!=h.ev_hash(root,H+'/changes/'+c['id']+'/'+n):g.fail(h,'Published handoff changed; preserve and republish, never edit sealed hashes: '+n)
    return p


def results_ok(h,root,c,expect_pass=True):
    packet=delivery_packet_ok(h,root,c);r=h.read_json(h.cp(root,c['id'],'OWNER_RESULTS.json'))
    if r.get('id')!=c['id'] or r.get('delivery_packet_sha256')!=h.digest(h.canonical(packet)):g.fail(h,'Owner results not bound to this handoff')
    source=r.get('owner_source');check_asset(h,root,source,'actual Owner feedback')
    nonempty(h,r.get('actual_connection'),'actual connection')
    brief=brief_input_ok(h,root,c);steps={s['id']:s for s in brief['steps']};rows=r.get('steps',[])
    if len(rows)!=len(steps) or {x.get('id') for x in rows}!=set(steps):g.fail(h,'Record each step pass/fail/not_executed; do not omit unexecuted tests')
    by={x['id']:x for x in rows}
    raw=h.child(root,source['path']).read_text(encoding='utf-8-sig')
    for x in rows:
        if x.get('status') not in ('pass','fail','not_executed'):g.fail(h,'Invalid Owner step result')
        nonempty(h,x.get('observation'),'Owner actual observation')
        if x['status']!='not_executed':
            quote=nonempty(h,x.get('source_quote'),'Owner quote for performed step')
            if quote not in raw:g.fail(h,'Owner step quote not found in feedback')
    if c['requirements']['device_related'] and any(steps[x['id']]['device_step'] and x['status']!='not_executed' for x in rows):
        dev=r.get('device_confirmation',{})
        ident=h.read_json(h.cp(root,c['id'],'FIRMWARE_IDENTITY.json'))
        if dev.get('confirmed') is not True or dev.get('hex_sha256','').lower()!=ident['artifact']['sha256'].lower():g.fail(h,'Actual device/HEX not confirmed for recorded hardware results')
        quote=nonempty(h,dev.get('source_quote'),'Owner device confirmation quote')
        if quote not in raw:g.fail(h,'Device confirmation absent from Owner feedback')
    if expect_pass:
        if any(x['status']=='fail' for x in rows):g.fail(h,'Owner reported FAIL; do not label UAT PASS')
        cov=coverage_ok(h,root,c)
        for row in cov['rows']:
            if row['disposition']=='planned_owner' and any(by[x]['status']!='pass' for x in row['step_ids']):g.fail(h,'Required acceptance not actually passed: '+row['id'])
    return r


def status_delivery(h,root,c):
    print('Delivery extension:',c['id'],'| additive evidence; historical task retained')
    for label,fn in [('actual distribution/form',lambda:profile_ok(h,root,c)),
      ('formal Firmware admission',lambda:formal_gate_ok(h,root,c)),
      ('Contract acceptance coverage',lambda:coverage_ok(h,root,c)),
      ('published actionable Owner brief',lambda:delivery_packet_ok(h,root,c))]:
        try:fn();print('PASS:',label)
        except (h.HarnessError,OSError,ValueError,KeyError,TypeError) as e:print('PENDING/BLOCKED:',label,'—',str(e)[:500])
    print('No app/device/model execution. Missing supplements are not installation failure. JAR != either installer validation.')


# ---- Explicitly Owner-dispatched dual-variant batch records; no compiler runner ----
def bp(h,root,bid,name='BATCH.json'):
    if not isinstance(bid,str) or not BID.fullmatch(bid):g.fail(h,'Batch ID must be WB-001 (3-6 digits)')
    return h.child(root,H+'/delivery/batches/'+bid+'/'+str(h.safe_rel(name)))


def batch_load(h,root,bid):return h.read_json(bp(h,root,bid))


def batch_inputs_hash(h,b):
    return h.digest(h.canonical({k:b.get(k) for k in ('id','owner_dispatch','included_tasks','source_candidate','delivery_form','variants','install_policy','required_tests','scope_review')}))


def batch_ready(h,root,b):
    check_asset(h,root,b['owner_dispatch'],'batch Owner dispatch')
    g.committed_inputs(h,root,b['source_candidate']['commit'])
    if g.fp(h,root)['sha256']!=b['source_candidate']['source_fingerprint']:g.fail(h,'Batch source candidate changed; no silently inherited feature changes')
    if b.get('delivery_form') not in ('installer_exe','installer_msi','app_image'):g.fail(h,'Batch is packaging validation, not JAR repetition')
    if b.get('install_policy',{}).get('relationship')!='exclusive_switchable':g.fail(h,'Owner chose mutually exclusive switchable variants')
    for k in ('identity','preserve_user_configuration','model_file_cleanup','rollback','version_compatibility'):nonempty(h,b['install_policy'].get(k),'batch install '+k)
    for t in b['included_tasks']:
        h.require_id(t['id']);check_asset(h,root,t.get('source_record'),'included task')
        nonempty(h,t.get('relationship_to_candidate'),'included task relevance')
        task=h.change(root,t['id'])
        if task.get('status')!='CLOSED':g.fail(h,'Only closed scoped integration tasks may qualify as already-tested batch inputs; do not silently call paused work passed')
        summary=h.read_json(h.cp(root,t['id'],'DELIVERY_RESULT.json'))
        if summary.get('scope')!='exact_tested_form_only':g.fail(h,'Included task lacks scoped delivery acceptance record')
        if summary.get('results_sha256')!=h.ev_hash(root,H+'/changes/'+t['id']+'/OWNER_RESULTS.json'):g.fail(h,'Included JAR test results changed after closure')
    variants=b.get('variants',{})
    selected=set(b.get('selected_variants',variants.keys()))
    if not selected or not selected.issubset(set(VARIANTS)) or set(variants)!=selected:g.fail(h,'Batch variants must exactly match the Owner-selected lite/model/both scope')
    roots=[]
    for name,v in variants.items():
        for k in ('recipe','input_manifest'):check_asset(h,root,v.get(k),'batch '+name+' '+k)
        nonempty(h,v.get('recipe_review'),'recipe/risk review')
        if v.get('side_effects_approved') is not True:g.fail(h,'Packaging scripts side effects must be reviewed/authorized, never automatic clean/kill')
        if type(v.get('model_enabled')) is not bool or v['model_enabled']!=(name=='model-bundled'):g.fail(h,'Variant local-model mode mismatch')
        inp=h.read_json(h.child(root,v['input_manifest']['path']))
        if inp.get('model_enabled')!=v['model_enabled'] or inp.get('model_family') is None:g.fail(h,'Explicit model recipe required')
        for x in inp.get('files',[]):
            base=root if x['workspace']=='windows' else h.external_root(root,x['workspace'])
            check_asset(h,base,x,'packaging input')
        if name=='model-bundled' and (not inp.get('model_files') or not set(inp['model_files']).issubset({x['path'] for x in inp.get('files',[])})):
            g.fail(h,'Model variant resources missing; do not silently downgrade or copy unrelated model family')
        out=h.safe_rel(v.get('output_root')).as_posix();required=H+'/delivery/batches/'+b['id']+'/artifacts/'+name
        if out!=required:g.fail(h,'Isolate outputs in this batch/variant artifact directory; never overwrite target or other variant')
        roots.append(out)
    if len(set(roots))!=len(roots):g.fail(h,'Variant outputs overlap')
    review=b.get('scope_review',{})
    nonempty(h,review.get('reviewer_session'),'batch scope reviewer')
    nonempty(h,review.get('analysis'),'batch scope changes since included tasks',20)
    if review.get('decision')!='pass':g.fail(h,'DLA must review cumulative candidate vs included tasks before packaging')
    tests=b.get('required_tests',{})
    base={'clean_install','launch','common_configuration','variant_ui','variant_runtime'}
    if not base.issubset(set(tests.get('per_variant',[]))):g.fail(h,'Each selected installer variant needs clean-install/launch/common/variant checks')
    if len(selected)==2 and not {'lite_to_model','model_to_lite'}.issubset(tests.get('switches',[])):g.fail(h,'When Owner selects both variants, test both switch directions')
    if len(selected)==1 and tests.get('switches'):g.fail(h,'Single-variant batch must not claim cross-variant switching was tested')
    if any('feature:'+t['id'] not in tests['per_variant'] for t in b['included_tasks']):g.fail(h,'Each included public feature must be covered in both variants')
    return b


def batch_approved(h,root,b):
    if b.get('status') not in ('APPROVED','BUILDING','OWNER_TEST','CLOSED'):g.fail(h,'Batch has not been approved by Owner')
    a=b.get('approval',{});check_asset(h,root,a.get('owner_record'),'batch approval')
    if a.get('inputs_sha256')!=batch_inputs_hash(h,b):g.fail(h,'Approved batch scope/recipes changed')
    if a.get('external_inputs_sha256')!=external_batch_inputs(h,root,b):g.fail(h,'Batch recipe/model-input files changed after approval')
    return batch_ready(h,root,b)


def external_batch_inputs(h,root,b):
    vals={}
    for name,v in b['variants'].items():
        vals[name]={k:h.ev_hash(root,v[k]['path']) for k in ('recipe','input_manifest')}
        inp=h.read_json(h.child(root,v['input_manifest']['path']))
        vals[name]['files']=[{'workspace':x['workspace'],'path':x['path'],'sha256':x['sha256']} for x in inp.get('files',[])]
    return h.digest(h.canonical(vals))


def batch_init(h,root,a):
    if bp(h,root,a.batch).exists():g.fail(h,'Batch already exists; do not replace its history')
    tasks=[]
    for cid in a.task:
        c=h.change(root,cid)
        tasks.append({'id':cid,'source_record':asset(h,root,H+'/changes/'+cid+'/change.json'),'relationship_to_candidate':''})
    anchor=g.committed_inputs(h,root,a.commit)
    b={'schema_version':1,'id':a.batch,'status':'DRAFT','created_at':h.now(),
       'owner_dispatch':asset(h,root,a.owner_record),'included_tasks':tasks,'source_candidate':anchor,
       'delivery_form':a.form,'approval':None,'selected_variants':sorted(set(a.variant)),'variants':{},
       'install_policy':{'relationship':'exclusive_switchable','identity':'','preserve_user_configuration':'',
                         'model_file_cleanup':'','rollback':'','version_compatibility':''},
       'required_tests':{'per_variant':['clean_install','launch','common_configuration','variant_ui','variant_runtime']+['feature:'+t['id'] for t in tasks],
                         'switches':['lite_to_model','model_to_lite'] if len(set(a.variant))==2 else []},
       'scope_review':{'reviewer_session':'','analysis':'','decision':'pending'}}
    for name in sorted(set(a.variant)):b['variants'][name]={'model_enabled':name=='model-bundled','recipe':None,'input_manifest':None,'recipe_review':'',
         'side_effects_approved':False,'output_root':H+'/delivery/batches/'+a.batch+'/artifacts/'+name}
    write_new(h,bp(h,root,a.batch),b)
    print('Batch DRAFT created from explicit Owner instruction. No build or approval; no automatic task schedule.')


def batch_receipt_ok(h,root,b,name):
    batch_approved(h,root,b)
    r=h.read_json(bp(h,root,b['id'],'variants/'+name+'/BUILD.json'))
    if r.get('batch_inputs_sha256')!=batch_inputs_hash(h,b) or r.get('variant')!=name or r.get('source_commit')!=b['source_candidate']['commit']:g.fail(h,'Variant build stale/mismatched')
    if r.get('exit_code')!=0 or not r.get('logs'):g.fail(h,'Variant build did not record actual successful execution')
    for x in r['logs']:check_asset(h,root,x,'variant build log')
    check_asset(h,root,r['primary'],'variant primary')
    if r.get('files')!=g.artifact_files(h,root,[b['variants'][name]['output_root']]):g.fail(h,'Variant outputs changed')
    check_asset(h,root,r.get('content_evidence'),'package contents evidence')
    ce=h.read_json(h.child(root,r['content_evidence']['path']))
    if ce.get('model_enabled')!=(name=='model-bundled') or ce.get('primary_sha256')!=r['primary']['sha256'] or ce.get('variant')!=name:g.fail(h,'Contents report must bind exact variant, config and primary')
    for key in ('config_observation','runtime_dependency_observation','model_observation','native_dependency_observation','inspection_method'):
        nonempty(h,ce.get(key),'variant contents '+key)
    inp=h.read_json(h.child(root,b['variants'][name]['input_manifest']['path']))
    expected={x['path']:x['sha256'].lower() for x in inp.get('files',[]) if x['path'] in inp.get('model_files',[])}
    if ce.get('model_family')!=inp.get('model_family'):g.fail(h,'Observed package model family differs from approved recipe')
    if ce.get('model_file_hashes',{})!=expected:g.fail(h,'Model payload hashes/complete inventory do not match approved input recipe')
    if name=='model-bundled' and not ce.get('model_file_hashes'):g.fail(h,'Model packaged contents unaccounted for')
    if name=='lite-no-local-model' and ce.get('model_file_hashes'):g.fail(h,'Lite artifact contaminated with model payload')
    return r


def batch_packet_ok(h,root,b):
    builds={v:batch_receipt_ok(h,root,b,v) for v in VARIANTS}
    packet=h.read_json(bp(h,root,b['id'],'OWNER_PACKET.json'))
    if packet.get('builds')!={v:h.digest(h.canonical(x)) for v,x in builds.items()}:g.fail(h,'Batch Owner packet not bound to both current builds')
    for key in ('input','brief'):check_asset(h,root,packet.get(key),'batch Owner '+key)
    return packet


def batch_handoff(h,root,b):
    builds={v:batch_receipt_ok(h,root,b,v) for v in VARIANTS}
    rel=H+'/delivery/batches/'+b['id']+'/OWNER_TEST_INPUT.json';inp=h.read_json(h.child(root,rel))
    if inp.get('batch')!=b['id']:g.fail(h,'Batch test input ID mismatch')
    for k in ('preconditions','recovery','result_return','install_target','installed_application_entry'):nonempty(h,inp.get(k),'batch test '+k)
    for key,required in [('per_variant',b['required_tests']['per_variant']),('switches',b['required_tests']['switches'])]:
        if set(inp.get(key,{}))!=set(required):g.fail(h,'Batch Owner instructions must cover every required test, not only package paths')
        for test in inp[key].values():
            nonempty(h,test.get('action'),'batch test action');nonempty(h,test.get('expected'),'batch expected')
    lines=['# '+b['id']+' 双版安装交测简报','同一应用二选一可切换；不是同时运行两版。没有自动安装/升级/关闭进程。',
           '本批任务：'+', '.join(t['id'] for t in b['included_tasks']),
           '共同源码候选：'+b['source_candidate']['commit'],'交付形式：'+b['delivery_form'],
           '安装目标：'+inp['install_target'],'安装后入口：'+inp['installed_application_entry'],
           '前置：'+inp['preconditions']]
    for v in VARIANTS:
        r=builds[v];lines+=['## '+v,'文件：`'+str(h.child(root,r['primary']['path']))+'`','SHA256：'+r['primary']['sha256']]
        for key,test in inp['per_variant'].items():lines += ['### '+key,test['action'],'预期：'+test['expected']]
    lines += ['## 两种切换方向']
    for key,test in inp['switches'].items():lines += ['### '+key,test['action'],'预期：'+test['expected']]
    lines += ['## 停止与恢复',inp['recovery'],'## 反馈',inp['result_return'],'生成本简报没有执行真实安装/功能/切换测试；不表示官网发布通过。']
    text='\n\n'.join(lines)+'\n';dest=bp(h,root,b['id'],'OWNER_BRIEF.md')
    for n in ('OWNER_BRIEF.md','OWNER_PACKET.json'):
        old=bp(h,root,b['id'],n)
        if old.exists():h.atomic(bp(h,root,b['id'],'history/'+g.uid()+'/'+n),old.read_bytes())
    h.atomic(dest,text.encode())
    packet={'schema_version':1,'batch':b['id'],'at':h.now(),'builds':{v:h.digest(h.canonical(x)) for v,x in builds.items()},
       'input':asset(h,root,rel),'brief':asset(h,root,dest.relative_to(root).as_posix()),'test_status':'not_executed'}
    h.write_json(bp(h,root,b['id'],'OWNER_PACKET.json'),packet)
    s=h.state(root);s.update(next_actor='Owner',next_mode='BATCH_OWNER_TEST')
    s['owner_action']={'required':True,'action':'按已输出的双版简报分别测试和双向切换，使用原始自然语言/截图反馈。'}
    s['test_action']={'required':True,'brief':packet['brief']['path'],'packet':H+'/delivery/batches/'+b['id']+'/OWNER_PACKET.json'}
    h.save_state(root,s);print(text);return packet


def batch_result_ok(h,root,b,name):
    packet=batch_packet_ok(h,root,b)
    build=batch_receipt_ok(h,root,b,name);r=h.read_json(bp(h,root,b['id'],'variants/'+name+'/OWNER_RESULT.json'))
    check_asset(h,root,r.get('owner_source'),'Owner package feedback')
    if r.get('owner_packet_sha256')!=h.digest(h.canonical(packet)):g.fail(h,'Owner result not bound to actionable batch test instructions')
    if r.get('build_sha256')!=h.digest(h.canonical(build)):g.fail(h,'Variant Owner result for another build')
    actual=r.get('tests',{})
    if set(actual)!=set(b['required_tests']['per_variant']):g.fail(h,'Per-variant required tests incomplete')
    raw=h.child(root,r['owner_source']['path']).read_text(encoding='utf-8-sig')
    for name,x in actual.items():
        if x.get('status')!='pass':g.fail(h,'Batch variant test not PASS: '+name)
        quote=nonempty(h,x.get('source_quote'),'Owner test quote');nonempty(h,x.get('observation'),'observed package behavior')
        if quote not in raw:g.fail(h,'Package test quote absent from Owner feedback')
    return r


def batch_complete(h,root,b):
    rs={v:batch_result_ok(h,root,b,v) for v in VARIANTS}
    builds={v:batch_receipt_ok(h,root,b,v) for v in VARIANTS}
    if len({x['primary']['sha256'] for x in builds.values()})!=2:g.fail(h,'Both variants have identical primary bytes; cannot count a renamed copy as dual delivery')
    switch=h.read_json(bp(h,root,b['id'],'SWITCH_RESULTS.json'));check_asset(h,root,switch.get('owner_source'),'Owner switch feedback')
    if switch.get('builds')!={v:h.digest(h.canonical(x)) for v,x in builds.items()}:g.fail(h,'Switch results not bound to exact pair')
    raw=h.child(root,switch['owner_source']['path']).read_text(encoding='utf-8-sig')
    for direction in b['required_tests']['switches']:
        x=switch.get('tests',{}).get(direction,{})
        if x.get('status')!='pass':g.fail(h,'Switch direction not verified: '+direction)
        for key in ('configuration_preservation','single_app_identity','model_behavior','recovery_assessment'):nonempty(h,x.get(key),'switch '+key)
        quote=nonempty(h,x.get('source_quote'),'Owner switch quote')
        if quote not in raw:g.fail(h,'Switch quote absent from Owner source')
    return builds,rs,switch


def batch_command(h,root,s,a):
    if a.cmd=='batch-init':batch_init(h,root,a);return
    b=batch_load(h,root,a.batch)
    if a.cmd in ('batch-pause','batch-resume','batch-cancel'):
        note=asset(h,root,a.owner_record);reason=nonempty(h,a.reason,'Owner scheduling reason')
        previous=dict(b)
        if a.cmd=='batch-resume':
            if b.get('status')!='PAUSED':g.fail(h,'Only explicitly PAUSED batches can resume')
            if s.get('active_change') or s.get('current_assignment') or s.get('active_delivery_batch'):g.fail(h,'Another task/batch is active')
            probe=dict(b);probe['status']='APPROVED';batch_approved(h,root,probe)
            b['status']='APPROVED';s.update(active_delivery_batch=a.batch,next_actor='DIB',next_mode='BATCH_BUILD')
            s['owner_action']={'required':False,'action':'Resume exact approved batch and old evidence; inputs were not reset.'}
        else:
            if b.get('status') in ('CLOSED','CANCELLED'):g.fail(h,'Closed/cancelled batch is historical, not a new scheduling target')
            if a.cmd=='batch-pause' and s.get('active_delivery_batch')!=a.batch:g.fail(h,'Pause requires this active batch')
            b['status']='PAUSED' if a.cmd=='batch-pause' else 'CANCELLED'
            if s.get('active_delivery_batch')==a.batch:s.pop('active_delivery_batch',None);h.wait_state(s)
        b.setdefault('schedule_history',[]).append({'event':a.cmd,'at':h.now(),'reason':reason,'owner_record':note})
        h.write_json(bp(h,root,a.batch,'history/'+g.uid()+'/BATCH.json'),previous)
        h.write_json(bp(h,root,a.batch),b);h.save_state(root,s)
        print('Owner scheduling recorded:',b['status'],'; original source/approval/artifacts retained, no test PASS or input reset.');return
    if a.cmd=='batch-status':
        print('Batch',b['id'],'status:',b['status'],'; install relationship: exclusive/switchable')
        for label,fn in [('approved recipes',lambda:batch_approved(h,root,b))]+[(v+' output',lambda v=v:batch_receipt_ok(h,root,b,v)) for v in VARIANTS]+[('both variants and switching',lambda:batch_complete(h,root,b))]:
            try:fn();print('PASS:',label)
            except (h.HarnessError,OSError,ValueError,KeyError,TypeError) as e:print('PENDING/BLOCKED:',label,'—',str(e)[:500])
        print('No builds/installations/tests performed by this command. No release authorization.');return
    if a.cmd=='batch-approve':
        if s.get('active_change') or s.get('current_assignment') or s.get('active_delivery_batch'):g.fail(h,'Only one active implementation/batch. Explicitly finish/park existing task first; never auto suspend WD-001')
        if b['status']!='DRAFT':g.fail(h,'Only DRAFT batch can be approved')
        batch_ready(h,root,b);b['approval']={'at':h.now(),'owner_record':asset(h,root,a.owner_record),
          'inputs_sha256':batch_inputs_hash(h,b),'external_inputs_sha256':external_batch_inputs(h,root,b)}
        b['status']='APPROVED';h.write_json(bp(h,root,a.batch),b)
        s.update(active_delivery_batch=a.batch,next_actor='DIB',next_mode='BATCH_BUILD')
        s['owner_action']={'required':False,'action':'DIB仅按批准配方在隔离批次目录构建；不自动安装或关闭现有客户端。'};h.save_state(root,s);print('BATCH APPROVED. No build command executed.');return
    batch_approved(h,root,b)
    if s.get('active_delivery_batch')!=a.batch:g.fail(h,'Not the active Owner-approved batch')
    if a.cmd=='batch-request-test':batch_handoff(h,root,b);return
    if a.cmd=='batch-owner-brief':batch_packet_ok(h,root,b);print(bp(h,root,b['id'],'OWNER_BRIEF.md').read_text(encoding='utf-8'));return
    if a.cmd=='batch-build-open':
        token=g.uid();start={'schema_version':1,'batch':a.batch,'variant':a.variant,'token':token,'at':h.now(),
          'batch_inputs_sha256':batch_inputs_hash(h,b),'source_fingerprint':g.fp(h,root)['sha256'],'source_commit':b['source_candidate']['commit'],
          'existing_outputs':{v:g.artifact_files(h,root,[b['variants'][v]['output_root']]) if h.child(root,b['variants'][v]['output_root']).exists() else {} for v in VARIANTS}}
        write_new(h,bp(h,root,a.batch,'builds/'+token+'/START.json'),start);print('BATCH BUILD TOKEN:',token,'; execute reviewed commands separately, never in live target.');return
    if a.cmd=='batch-build-finish':
        if not re.fullmatch(r'[A-Za-z0-9-]+',a.token):g.fail(h,'Invalid build token')
        st=h.read_json(bp(h,root,a.batch,'builds/'+a.token+'/START.json'))
        if st['variant']!=a.variant or st['batch_inputs_sha256']!=batch_inputs_hash(h,b) or st['source_fingerprint']!=g.fp(h,root)['sha256']:g.fail(h,'Batch build inputs changed')
        report=h.read_json(h.child(root,a.report))
        if report.get('exit_code')!=0 or not report.get('logs'):g.fail(h,'Actual build exit/log record required')
        primary=h.safe_rel(report.get('primary')).as_posix();out=b['variants'][a.variant]['output_root']
        if not primary.startswith(out+'/'):g.fail(h,'Output is not isolated inside the selected variant')
        suffix='.msi' if b['delivery_form']=='installer_msi' else '.exe'
        if not primary.lower().endswith(suffix):g.fail(h,'Expected '+suffix+' as packaging primary')
        other=next(v for v in VARIANTS if v!=a.variant)
        actual_other=g.artifact_files(h,root,[b['variants'][other]['output_root']]) if h.child(root,b['variants'][other]['output_root']).exists() else {}
        if actual_other!=st['existing_outputs'][other]:g.fail(h,'Other variant output changed during this build')
        nonempty(h,report.get('command'),'actual packaging command')
        logs=[asset(h,root,p) for p in report['logs']]
        rec={**st,'finished_at':h.now(),'primary':asset(h,root,primary),'files':g.artifact_files(h,root,[out]),
             'logs':logs,'exit_code':0,'command':report['command'],'content_evidence':asset(h,root,report.get('content_evidence'))}
        p=bp(h,root,a.batch,'variants/'+a.variant+'/BUILD.json')
        if p.exists():h.atomic(bp(h,root,a.batch,'history/'+g.uid()+'/'+a.variant+'-BUILD.json'),p.read_bytes())
        h.write_json(p,rec)
        # If this fails the receipt remains an honest failed candidate; batch status will not PASS.
        batch_receipt_ok(h,root,b,a.variant);print('Variant build evidence bound; execution truth/runtime/Owner results not implied.');return
    if a.cmd=='batch-register-result':
        batch_receipt_ok(h,root,b,a.variant);report=h.read_json(h.child(root,a.report));check_asset(h,root,report.get('owner_source'))
        dest=bp(h,root,a.batch,'variants/'+a.variant+'/OWNER_RESULT.json')
        if dest.exists():h.atomic(bp(h,root,a.batch,'history/'+g.uid()+'/'+a.variant+'-OWNER_RESULT.json'),dest.read_bytes())
        h.write_json(dest,report);print('Owner report preserved; batch-status determines coverage, no automatic PASS.');return
    if a.cmd=='batch-archive-plan':
        batch_complete(h,root,b)
        paths=[];base=bp(h,root,a.batch).parent
        for p in base.rglob('*'):
            rel=p.relative_to(base).as_posix()
            if p.is_file() and rel.split('/')[0] not in ('artifacts','staging','history') and p.name not in ('ARCHIVE_PLAN.json','ARCHIVE_GIT_PLAN.ps1','ARCHIVE_RECEIPT.json'):
                paths.append(p.relative_to(root).as_posix())
        gr,prefix=g.repo_info(h,root)
        plan={'id':a.batch,'files':{r:h.ev_hash(root,r) for r in paths},'at':h.now()}
        h.write_json(bp(h,root,a.batch,'ARCHIVE_PLAN.json'),plan)
        ps="Set-Location -LiteralPath "+g.ps_quote(str(gr))+"\n$existing=@(git diff --cached --name-only)\nif ($LASTEXITCODE -ne 0 -or $existing.Count -gt 0) { throw 'Inspect existing index; no auto reset' }\n$paths=@(\n"+",\n".join(g.ps_quote(prefix+r) for r in paths)+"\n)\ngit --literal-pathspecs add -- $paths\nif ($LASTEXITCODE -ne 0) { throw 'git add failed' }\ngit diff --cached --check\nif ($LASTEXITCODE -ne 0) { throw 'staged check failed' }\ngit --no-pager diff --cached --stat\n# Owner inspects staged diff, then explicitly commits, checks exit code; existing identical commit may be verified/reused.\n"
        h.atomic(bp(h,root,a.batch,'ARCHIVE_GIT_PLAN.ps1'),ps.encode('utf-8-sig'));print('Batch record archive plan generated, not executed; large artifacts/models excluded.');return
    if a.cmd=='batch-archive-check':
        batch_complete(h,root,b);p=h.read_json(bp(h,root,a.batch,'ARCHIVE_PLAN.json'))
        for r,sha in p['files'].items():
            if h.ev_hash(root,r)!=sha:g.fail(h,'Archive content changed')
        rev=g.verify_saved_files(h,root,a.commit,list(p['files']))
        h.write_json(bp(h,root,a.batch,'ARCHIVE_RECEIPT.json'),{'commit':rev,'plan_sha256':h.digest(h.canonical(p)),'at':h.now()});print('Batch archive verified.');return
    if a.cmd=='batch-close':
        batch_complete(h,root,b);plan=h.read_json(bp(h,root,a.batch,'ARCHIVE_PLAN.json'));receipt=h.read_json(bp(h,root,a.batch,'ARCHIVE_RECEIPT.json'))
        if receipt.get('plan_sha256')!=h.digest(h.canonical(plan)):g.fail(h,'Batch archive stale')
        for r,sha in plan['files'].items():
            if sha!=h.ev_hash(root,r):g.fail(h,'Batch result changed since archive')
        g.verify_saved_files(h,root,receipt['commit'],list(plan['files']))
        b.update(status='CLOSED',closed_at=h.now(),closure='selected_variants_tested_not_published');h.write_json(bp(h,root,a.batch),b)
        s.pop('active_delivery_batch',None);h.wait_state(s);h.save_state(root,s);print('Batch closed at declared test scope. No release/push/upload, no automatic next task.');return
    g.fail(h,'Unknown batch command')


def make_parser(h):
    p=g.make_parser(h);sub=next(a for a in p._actions if isinstance(a,argparse._SubParsersAction))
    for name in ('delivery-status','delivery-init','handoff-preview','handoff-publish','owner-brief','results-check','firmware-admit'):
        q=sub.add_parser(name);q.add_argument('--id',required=True);q.add_argument('--role',choices=['DLA'],default='DLA')
        if name=='delivery-init':q.add_argument('--artifact')
        if name=='firmware-admit':q.add_argument('--gate',required=True)
    q=sub.add_parser('recipe-status');q.add_argument('--role',choices=['DLA'],default='DLA')
    q=sub.add_parser('release-status');q.add_argument('--role',choices=['DLA'],default='DLA')
    q=sub.add_parser('firmware-status');q.add_argument('--role',choices=['DLA'],default='DLA')
    q=sub.add_parser('firmware-discover');q.add_argument('--role',choices=['DLA'],default='DLA');q.add_argument('--limit',type=int,default=20);q.add_argument('--json',action='store_true')
    q=sub.add_parser('firmware-intake');q.add_argument('--id',required=True);q.add_argument('--gate',required=True);q.add_argument('--title');q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('firmware-sync-baseline');q.add_argument('--gate',required=True);q.add_argument('--windows-change',required=True);q.add_argument('--evidence-record',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('firmware-mark-consumed');q.add_argument('--gate',required=True);q.add_argument('--windows-change',required=True);q.add_argument('--evidence-record',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    for name in ('batch-init','batch-status','batch-approve','batch-build-open','batch-build-finish','batch-register-result','batch-request-test','batch-owner-brief','batch-archive-plan','batch-archive-check','batch-close','batch-pause','batch-resume','batch-cancel'):
        q=sub.add_parser(name);q.add_argument('--batch',required=True)
        q.add_argument('--role',choices=['DIB'] if name in ('batch-build-open','batch-build-finish') else ['DLA'],required=name!='batch-status',default='DLA')
        if name=='batch-init':q.add_argument('--task',action='append',required=True);q.add_argument('--owner-record',required=True);q.add_argument('--commit',default='HEAD');q.add_argument('--form',choices=['app_image','installer_exe','installer_msi'],default='installer_exe');q.add_argument('--variant',action='append',choices=VARIANTS,required=True,help='Owner-selected: lite, model, or both by repeating --variant')
        if name=='batch-approve':q.add_argument('--owner-record',required=True)
        if name in ('batch-pause','batch-resume','batch-cancel'):q.add_argument('--owner-record',required=True);q.add_argument('--reason',required=True)
        if name in ('batch-build-open','batch-build-finish','batch-register-result'):q.add_argument('--variant',choices=VARIANTS,required=True)
        if name in ('batch-build-finish','batch-register-result'):q.add_argument('--report',required=True)
        if name=='batch-build-finish':q.add_argument('--token',required=True)
        if name=='batch-archive-check':q.add_argument('--commit',default='HEAD')
    return p


def run(h,argv=None):
    a=h.parser().parse_args(argv);root=Path(a.repo).expanduser().resolve() if a.repo else Path(h.__file__).resolve().parents[4]
    s=h.state(root);policy(h,root);g.policy_ok(h,root)
    if a.cmd=='firmware-status':
        fwintake.status(h,root);return 0
    if a.cmd=='firmware-discover':
        if a.limit<1 or a.limit>100:g.fail(h,'--limit must be 1..100')
        fwintake.discover(h,root,a.limit,a.json);return 0
    if a.cmd in ('firmware-intake','firmware-sync-baseline','firmware-mark-consumed'):
        with h.lock(root):
            if a.cmd=='firmware-intake':fwintake.intake(h,root,a.id,a.gate,a.role,a.title)
            elif a.cmd=='firmware-sync-baseline':fwintake.baseline(h,root,a.gate,a.windows_change,a.evidence_record,a.role)
            else:fwintake.mark_consumed(h,root,a.gate,a.windows_change,a.evidence_record,a.role)
        return 0
    if a.cmd=='release-status':
        policy_data=h.read_json(h.child(root,H+'/releases/POLICY.json'))
        threshold=int(policy_data.get('reminder_threshold',5))
        closed=[]
        for c0 in h.all_changes(root):
            if c0.get('status')=='CLOSED':
                rp=h.cp(root,c0['id'],'DELIVERY_RESULT.json')
                if rp.is_file(): closed.append(c0['id'])
        used=set()
        batches=h.child(root,H+'/delivery/batches')
        if batches.exists():
            for bp0 in batches.iterdir():
                if (bp0/'BATCH.json').is_file():
                    try:
                        br=h.read_json(bp0/'BATCH.json')
                        if br.get('status')!='CANCELLED': used.update(x.get('id') for x in br.get('included_tasks',[]))
                    except Exception: pass
        pending=[x for x in closed if x not in used]
        print('Release-batch eligible closed JAR tasks:',len(pending),pending)
        if len(pending)>=threshold: print('REMINDER: threshold reached. Ask Owner whether to start a Release Batch and choose lite / local-model / both. Do not auto-create.')
        else: print('No automatic batch. Reminder threshold:',threshold,'; Owner may still request one at any time.')
        return 0
    if a.cmd=='recipe-status':
        recipes=h.read_json(h.child(root,H+'/delivery/RECIPES.json'))
        for r in recipes['recipes']:
            try:
                base=root if r['workspace']=='windows' else h.external_root(root,r['workspace'])
                current=h.ev_hash(base,r['script']);status='MATCH' if current==r['script_sha256'] else 'CHANGED / re-audit before using recipe'
            except (h.HarnessError,OSError) as e:status='UNKNOWN: '+str(e)
            print(r['id'],status,'|',r['form'],'|',r['output'],'| static recipe, NOT build PASS')
        print('Model resources, install switching and both executable variants still need explicit batch authorization and real evidence.');return 0
    if a.cmd.startswith('batch-'):
        if a.cmd=='batch-status':batch_command(h,root,s,a)
        else:
            with h.lock(root):batch_command(h,root,s,a)
        return 0
    if a.cmd in ('delivery-status','delivery-init','firmware-admit','handoff-preview','handoff-publish','owner-brief','results-check'):
        c=h.change(root,a.id)
        if a.cmd=='delivery-status':status_delivery(h,root,c);return 0
        if a.cmd=='owner-brief':delivery_packet_ok(h,root,c);print(h.cp(root,a.id,'OWNER_BRIEF.md').read_text(encoding='utf-8'));return 0
        if a.cmd=='results-check':results_ok(h,root,c);print('Recorded Owner step coverage PASS; input assertions not independent proof of tester identity.');return 0
        with h.lock(root):
            h.require_active(root,s,a.id)
            if a.cmd=='delivery-init':init_delivery(h,root,c,a.artifact)
            elif a.cmd=='firmware-admit':formal_gate_bind(h,root,c,a.gate)
            elif a.cmd=='handoff-preview':
                txt=render_brief(h,root,c,False);p=h.cp(root,c['id'],'delivery-previews/'+g.uid()+'.md');h.atomic(p,txt.encode());print(txt);print('PREVIEW ONLY:',p)
            elif a.cmd=='handoff-publish':publish(h,root,c)
        return 0
    if s.get('active_delivery_batch') and a.cmd in ('new','intake','approve','activate','wait'):
        g.fail(h,'Owner-approved packaging batch active. Do not start another production task or silently clear batch; finish/reconcile first.')
    c=h.change(root,a.id) if getattr(a,'id',None) and h.cp(root,a.id,'change.json').exists() else None
    if a.cmd=='request-test':all_inputs(h,root,c)
    if c and a.cmd in ('archive-plan','archive-check','close'):delivery_packet_ok(h,root,c);results_ok(h,root,c)
    if c and a.cmd=='record-check' and a.check in ('real_device','owner_uat') and a.status=='pass':
        results_ok(h,root,c)
        rr=H+'/changes/'+a.id+'/OWNER_RESULTS.json'
        if not any(h.safe_rel(p).as_posix()==rr for p in a.evidence):g.fail(h,'Include OWNER_RESULTS.json among PASS evidence so actual step mapping stays bound')
    if c and a.cmd in ('record-check','request-fix','reopen-contract','close'):
        with h.lock(root):retained(h,root,c,'before-'+a.cmd)
    # Extend archive inputs while preserving core Git behavior, including hf01 normalization.
    original=g.closure_assets
    if c and a.cmd=='archive-plan':
        def extended(hh,rr,cc):
            paths=original(hh,rr,cc)
            paths += [H+'/changes/'+cc['id']+'/'+n for n in SIDE if hh.cp(rr,cc['id'],n).is_file()]
            res=hh.read_json(hh.cp(rr,cc['id'],'OWNER_RESULTS.json'))
            paths.append(res['owner_source']['path'])
            cov=hh.read_json(hh.cp(rr,cc['id'],'ACCEPTANCE_COVERAGE.json'))
            for row in cov['rows']:
                if row.get('owner_exception'):paths.append(row['owner_exception']['path'])
                for ev in row.get('evidence',[]):
                    if ev.get('workspace')=='windows':paths.append(ev['path'])
            return g.normalized_record_paths(hh,paths)
        g.closure_assets=extended
    try:result=g.run(h,argv)
    finally:g.closure_assets=original
    if result==0:
        if a.cmd=='request-test':
            with h.lock(root):publish(h,root,h.change(root,a.id))
        if a.cmd=='guard-status':status_delivery(h,root,h.change(root,a.id))
        if a.cmd=='status':
            print('Delivery policy: serial JAR tasks; Owner starts installer batch and selects lite / local-model / both; variants exclusive/switchable.')
            print('Active packaging batch:',s.get('active_delivery_batch') or 'NONE')
            if s.get('active_change'):print('Run delivery-status / owner-brief for actual test eligibility and concrete instructions; old packet identity alone is insufficient.')
        if c and a.cmd=='close':
            with h.lock(root):
                out={'id':c['id'],'at':h.now(),'scope':'exact_tested_form_only','delivery_profile':h.read_json(h.cp(root,c['id'],'DELIVERY_PROFILE.json')),
                     'packet_sha256':h.digest(h.canonical(h.read_json(h.cp(root,c['id'],'DELIVERY_PACKET.json')))),
                     'results_sha256':h.ev_hash(root,H+'/changes/'+c['id']+'/OWNER_RESULTS.json'),
                     'installer_coverage':{v:'not_covered_by_this_jar_task' for v in VARIANTS}}
                h.write_json(h.cp(root,c['id'],'DELIVERY_RESULT.json'),out)
    return result
