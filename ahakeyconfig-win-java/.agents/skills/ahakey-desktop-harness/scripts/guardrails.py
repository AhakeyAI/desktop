"""AhaKey v1.2 delivery guards. Stdlib only. Git reads plus explicit Owner-generated staging plans; no automatic product/device/reference writes.
Structured assertions/hashes are not proof of human identity, review quality, or execution truth.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid

GUARD_VERSION = 2
PATH_NORMALIZATION_HOTFIX = 'v0.4.0-hf01'
H = '.ahakey-desktop-harness'
POLICY_FILE = H + '/GUARD_POLICY_SEAL.json'
_SHA = re.compile(r'[0-9a-f]{64}\Z')
PLACEHOLDERS = re.compile(r'(?i)(\bTODO\b|\bTBD\b|\{\{|待填写|请填写|<fill|replace.me)')

def uid():
    return datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '-' + uuid.uuid4().hex[:6]

def fail(h, msg):
    raise h.HarnessError(msg)

def text(h, value, label, minlen=4):
    if not isinstance(value, str) or len(value.strip()) < minlen or PLACEHOLDERS.search(value):
        fail(h, 'Incomplete/placeholder ' + label)
    return value

def fp(h, root):
    return h.source_fingerprint(root)

def git(h, root, args, data=None, ok=(0,)):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0', GIT_TERMINAL_PROMPT='0')
    try:
        p = subprocess.run(['git', '--no-optional-locks', '-c', 'core.fsmonitor=false', '-c', 'core.quotePath=false',
                            '-C', str(root)] + list(args), input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=env, timeout=45)
    except (OSError, subprocess.TimeoutExpired) as e:
        fail(h, 'Read-only Git unavailable: ' + str(e))
    if p.returncode not in ok:
        fail(h, 'Read-only git ' + ' '.join(args[:4]) + ': ' + p.stderr.decode('utf-8', 'replace')[:1500])
    return p.stdout

def repo_info(h, root):
    gr = Path(git(h, root, ['rev-parse','--show-toplevel']).decode('utf-8').strip()).resolve()
    if not root.is_relative_to(gr): fail(h, 'Windows root is not within Git worktree')
    prefix = root.relative_to(gr).as_posix()
    return gr, ('' if prefix == '.' else prefix + '/')

def commit_id(h, root, rev):
    if not isinstance(rev,str) or not re.fullmatch(r'(HEAD|[0-9a-fA-F]{7,64})',rev):
        fail(h, 'Use HEAD or a literal commit ID; no arbitrary revision expressions')
    return git(h, root, ['rev-parse','--verify',rev+'^{commit}']).decode().strip()

def tree(h, root, rev):
    out = {}
    for entry in git(h, root, ['ls-tree','-r','-z',rev]).split(b'\0'):
        if not entry: continue
        meta, path = entry.split(b'\t',1)
        mode, kind, oid = meta.decode().split()
        out[path.decode('utf-8')] = {'mode':mode,'kind':kind,'oid':oid}
    return out

def blobs(h, root, objects):
    ids = sorted(set(objects))
    if not ids: return {}
    raw = git(h, root, ['cat-file','--batch'], ('\n'.join(ids)+'\n').encode())
    pos=0; result={}
    for expected in ids:
        end=raw.find(b'\n',pos)
        if end < 0: fail(h,'Malformed git cat-file output')
        header=raw[pos:end].decode().split(); pos=end+1
        if len(header)!=3 or header[0]!=expected or header[1]!='blob': fail(h,'Unsupported/missing Git blob')
        n=int(header[2]); result[expected]=raw[pos:pos+n]; pos+=n+1
    return result

def equivalent(a,b):
    if a==b: return True
    # Only explicit CRLF/LF equivalence for valid UTF-8 text, never filters or binaries.
    if b'\0' in a or b'\0' in b: return False
    try: return a.decode('utf-8').replace('\r\n','\n') == b.decode('utf-8').replace('\r\n','\n')
    except UnicodeDecodeError: return False

def match_old_hash(h,b,sha):
    if h.digest(b)==sha:return b
    if b'\0' not in b:
        try:
            b.decode('utf-8')
            for v in (b.replace(b'\r\n',b'\n'),b.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')):
                if h.digest(v)==sha:return v
        except UnicodeDecodeError:pass
    return None

def product_path(h,p):
    parts=p.split('/')
    return not any(x in h.SKIP_DIRS or x.startswith('AhaKey-Windows-Desktop-Harness-v') for x in parts[:-1]) and parts[-1] not in h.RUNTIME_ROOT_FILES and parts[-1] not in ('AGENTS.md','AGENTS.override.md','.gitignore') and not parts[-1].startswith('AhaKey-Windows-')


def recovery_evidence(h, root):
    """Reviewed, exact recovery artifacts; never a general dirty-file exemption."""
    manifest = h.child(root, H + '/RECOVERY_EVIDENCE.json')
    if not manifest.exists():
        return {}
    rec = h.read_json(manifest)
    if rec.get('kind') != 'route-hf01-recovery-evidence':
        fail(h, 'Unknown recovery evidence classification')
    owner = rec['owner_record']
    if h.ev_hash(root, owner['path']) != owner['sha256']:
        fail(h, 'Recovery evidence Owner record changed')
    expected = {'.rollback-backups/20261010T084508/' + n for n in
                ('status-before.txt', 'tracked-worktree.patch', 'untracked-before.txt')}
    rows = rec.get('files', [])
    if len(rows) != 3 or {r['path'] for r in rows} != expected:
        fail(h, 'Recovery evidence must identify only the three reviewed artifacts')
    result = {}
    for row in rows:
        rel = row['path']
        backup = H + '/maintenance/route-hf01/content/' + rel.rsplit('/', 1)[1]
        if row.get('content_copy') != backup or not _SHA.fullmatch(row.get('sha256', '')):
            fail(h, 'Invalid recovery content binding: ' + rel)
        if h.ev_hash(root, rel) != row['sha256'] or h.ev_hash(root, backup) != row['sha256']:
            fail(h, 'Recovery evidence missing/changed: ' + rel)
        if h.child(root, rel).read_bytes() != h.child(root, backup).read_bytes():
            fail(h, 'Recovery content mismatch: ' + rel)
        result[rel] = row['sha256']
    return result


def _preserved_foreign_path(h,root,c):
    return h.cp(root,c['id'],'preserved_foreign_inputs.json')

def preserved_foreign_entries(h,root,c):
    """Read v1.2 preserved in-repo foreign inputs. Tolerates the narrow v1.1 hotfix shapes."""
    p=_preserved_foreign_path(h,root,c)
    if not p.is_file(): return {}
    obj=h.read_json(p); out={}
    raw=obj.get('inputs', obj.get('files', obj.get('paths', {})))
    if isinstance(raw,dict):
        for rel,val in raw.items():
            if isinstance(val,str): sha=val
            elif isinstance(val,dict): sha=val.get('sha256') or val.get('hash')
            else: continue
            if isinstance(sha,str) and _SHA.fullmatch(sha): out[h.safe_rel(rel).as_posix()]=sha
    elif isinstance(raw,list):
        for row in raw:
            if isinstance(row,dict):
                rel=row.get('path'); sha=row.get('sha256') or row.get('hash')
                if isinstance(rel,str) and isinstance(sha,str) and _SHA.fullmatch(sha): out[h.safe_rel(rel).as_posix()]=sha
    # Backward-compatible single record.
    if not out and isinstance(obj.get('path'),str) and isinstance(obj.get('sha256'),str) and _SHA.fullmatch(obj['sha256']):
        out[h.safe_rel(obj['path']).as_posix()]=obj['sha256']
    return out

def preserved_foreign_ok(h,root,c):
    entries=preserved_foreign_entries(h,root,c)
    for rel,expected in entries.items():
        p=h.child(root,rel)
        if not p.is_file() or h.digest(p.read_bytes())!=expected:
            fail(h,'PRESERVED_FOREIGN_CHANGED: '+rel+'; do not restore/stash automatically, ask Owner/DLA to reconcile')
    return entries

def candidate_preserve_foreign(h,root,c,paths,owner_record):
    owner=asset_record(h,root,owner_record)
    start=h.read_json(h.cp(root,c['id'],'start-fingerprint.json'))
    current=h.source_fingerprint(root).get('files',{})
    existing=preserved_foreign_entries(h,root,c)
    accepted=dict(existing)
    rows=[]
    for raw in paths:
        rel=h.safe_rel(raw).as_posix(); p=h.child(root,rel)
        if not p.is_file(): fail(h,'Preserved foreign input missing: '+rel)
        sha=h.digest(p.read_bytes())
        # Strong default: must have existed exactly this way at task activation.
        start_sha=start.get('files',{}).get(rel)
        if start_sha and start_sha!=sha:
            fail(h,'Not pre-existing at task start: '+rel+'; do not hide new out-of-scope drift')
        if not start_sha and current.get(rel)!=sha:
            fail(h,'Cannot establish preserved foreign identity: '+rel)
        accepted[rel]=sha; rows.append({'path':rel,'sha256':sha,'start_sha256':start_sha})
    rec={'schema_version':2,'id':c['id'],'at':h.now(),'owner_record':owner['path'],'owner_sha256':owner['sha256'],
         'inputs':{rel:{'sha256':sha} for rel,sha in sorted(accepted.items())},
         'newly_accepted':rows,
         'meaning':'Owner-bound pre-existing in-repo dirty inputs. Preserved unchanged, excluded from this task candidate, never auto-restored/stashed/committed.'}
    h.write_json(_preserved_foreign_path(h,root,c),rec)
    print('PRESERVED FOREIGN RECORDED:',', '.join(r['path'] for r in rows))
    return rec

def committed_inputs(h,root,rev='HEAD',subset=None):
    recovery = recovery_evidence(h, root)
    gr,prefix=repo_info(h,root); rev=commit_id(h,root,rev)
    tr=tree(h,gr,rev)
    current=fp(h,root)['files']
    paths=set(current)|{p[len(prefix):] for p in tr if p.startswith(prefix) and product_path(h,p[len(prefix):])}
    if subset is not None:paths=set(subset)
    paths -= set(recovery)
    selected={prefix+p:tr[prefix+p] for p in paths if prefix+p in tr}
    for p,x in selected.items():
        if x['kind']!='blob' or x['mode'] not in ('100644','100755'): fail(h,'Unsupported link/submodule in candidate: '+p)
    bs=blobs(h,gr,[x['oid'] for x in selected.values()])
    missing=[]; norms=[]
    for rel in sorted(paths):
        x=selected.get(prefix+rel); p=h.child(root,rel)
        if not p.is_file():
            if x:missing.append(rel+' (still present in commit)')
            continue
        if not x:missing.append(rel+' (not committed)');continue
        b=p.read_bytes(); old=bs[x['oid']]
        if not equivalent(b,old):missing.append(rel+' (differs from commit)')
        elif b!=old:norms.append(rel)
    if missing:fail(h,'GIT_SAVE_REQUIRED: '+', '.join(missing[:20])+'; no automatic add/commit/reset')
    return {'commit':rev,'repository':str(gr),'prefix':prefix,'source_fingerprint':fp(h,root)['sha256'],
            'nonproduction_recovery_evidence': recovery,
            'text_eol_equivalent':norms,'comparison':'Git blobs vs working bytes; UTF-8 CRLF/LF equivalence only; no filters/hooks executed.'}

def foreign_snapshot(h,root):
    gr,prefix=repo_info(h,root)
    if not prefix:return {'files':{},'coverage':'Windows is Git root; governed separately'}
    names=set()
    for args in (['ls-files','-z'],['ls-files','--others','--exclude-standard','-z']):
        names.update(x.decode('utf-8') for x in git(h,gr,args).split(b'\0') if x)
    out={}
    for rel in sorted(names):
        if rel.startswith(prefix):continue
        if any(x in ('.git','target','build','node_modules','.gradle','__pycache__') for x in rel.split('/')):continue
        p=h.child(gr,rel)
        if p.is_file():out[rel]=h.digest(p.read_bytes())
        elif not p.exists():out[rel]='MISSING'
        else:out[rel]='NON_REGULAR'
    return {'files':out,'coverage':'Tracked and nonignored untracked sibling files; build/dependency dirs excluded. External Firmware/source repos not frozen.'}

def governance_snapshot(h,root):
    paths=set()
    for base in (root/'.agents',):
        if base.exists():
            for b,dirs,names in os.walk(base,followlinks=False):
                for d in dirs:
                    if h.linked(Path(b)/d):fail(h,'Linked governance directory')
                dirs[:]=[d for d in dirs if d!='__pycache__']
                for n in names:
                    if not n.endswith('.pyc'):paths.add((Path(b)/n).relative_to(root).as_posix())
    for rel in ('AGENTS.md','AGENTS.override.md','.gitignore'):
        if (root/rel).exists():paths.add(rel)
    if (root/H/'RECOVERY_EVIDENCE.json').exists():paths.add(H+'/RECOVERY_EVIDENCE.json')
    for rel in ('RULES.md','OPERATING_MODE.md','GUIDE.md','GUARDED_DELIVERY.md','DISTRIBUTION_DELIVERY.md','V1_RUNTIME.md','FIRMWARE_INTAKE.md','CONTRACT_REVISION.md','OWNER_PREVIEW.md','EVIDENCE_STREAMS.md','PRESERVED_FOREIGN.md','PREVIEW_ITERATION.md','delivery/POLICY.json','delivery/RECIPES.json','delivery/WD001_BRIEF_SEED.json','releases/POLICY.json'):
        if (root/H/rel).exists():paths.add(H+'/'+rel)
    for folder in ('templates','prompts'):
        p=root/H/folder
        if p.exists():
            for f in p.rglob('*'):
                if f.is_file():paths.add(f.relative_to(root).as_posix())
    return {r:h.ev_hash(root,r) for r in sorted(paths)}

def policy_ok(h,root):
    seal=h.read_json(h.child(root,POLICY_FILE))
    cur=governance_snapshot(h,root)
    if cur!=seal.get('files'):
        old=seal.get('files',{}); delta=[p for p in set(old)|set(cur) if old.get(p)!=cur.get(p)]
        fail(h,'PROTECTED_GOVERNANCE_CHANGED: '+', '.join(sorted(delta)[:12])+'; use a reviewed upgrade, do not reseal by hand')
    return h.digest(h.canonical(seal))

def origin(h,root,c):
    p=h.cp(root,c['id'],'guard-origin.json')
    if not p.is_file():fail(h,'Guard origin absent. Use baseline-start before approve, or supported active upgrade; never rebaseline current code manually.')
    o=h.read_json(p)
    actual=h.ev_hash(root,(h.cp(root,c['id'],'start-fingerprint.json')).relative_to(root).as_posix())
    if actual!=o.get('start_file_sha256'):fail(h,'ORIGINAL_BASELINE_CHANGED: immutable task start must survive pause/resume')
    policy_ok(h,root)
    cur=foreign_snapshot(h,root)
    foreign_base=o.get('foreign',{})
    accept=h.cp(root,c['id'],'foreign_acceptance.json')
    if accept.exists():
        ar=h.read_json(accept)
        if ar.get('owner_sha256')!=h.ev_hash(root,ar.get('owner_record')):fail(h,'Foreign reconciliation approval changed')
        foreign_base=ar['accepted_snapshot']
    if cur['files']!=foreign_base.get('files'):
        old=foreign_base.get('files',{});delta=[p for p in set(old)|set(cur['files']) if old.get(p)!=cur['files'].get(p)]
        fail(h,'SIBLING_WORKSPACE_CHANGED: '+', '.join(sorted(delta)[:12])+'; classify ownership in a reviewed reconciliation, no auto restore')
    return o

def changes(h,root,c):
    o=origin(h,root,c); start=h.read_json(h.cp(root,c['id'],'start-fingerprint.json'))
    cur=h.scope_diff(root,c)
    changed=[p for p in sorted(set(start['files'])|set(cur['files'])) if start['files'].get(p)!=cur['files'].get(p)]
    return o,start,cur,changed

def external_ref_state(h,root):
    # Configuration identity only. Source/Firmware content changes are checked on pinned refs by v0.3 engine.
    p=h.child(root,H+'/local.json')
    return h.read_json(p) if p.exists() else {}

def make_origin(h,root,c,kind):
    start=h.cp(root,c['id'],'start-fingerprint.json')
    if not start.is_file():fail(h,'Missing original start fingerprint, cannot reconstruct by declaring current code the start')
    p=h.cp(root,c['id'],'guard-origin.json')
    if p.exists():return origin(h,root,c)
    o={'schema_version':1,'id':c['id'],'captured_at':h.now(),'kind':kind,
       'start_file_sha256':h.digest(start.read_bytes()),'captured_code':fp(h,root),
       'git':h.git_info(root),'foreign':foreign_snapshot(h,root),'policy_sha256':policy_ok(h,root),
       'last_verified_baseline':h.read_json(h.child(root,H+'/VERIFIED_BASELINE.json')) if h.child(root,H+'/VERIFIED_BASELINE.json').exists() else None,
       'limitations':'Captured current bytes are not proof of pre-task behavior or UAT. Original fingerprint retained, never substituted. Legacy governance coverage begins at upgrade.'}
    h.write_json(p,o)
    # Local recovery copy for future tasks (private/ignored), never a source edit.
    for rel in o['captured_code']['files']:
        b=h.child(root,rel).read_bytes()
        h.atomic(h.cp(root,c['id'],'recovery/current-at-guard-start/'+rel),b)
    return o

def history(h,root,c,event):
    eid=uid(); dest=h.cp(root,c['id'],'history/'+eid+'-'+event)
    source=h.cp(root,c['id'],'change.json').parent
    refs={}
    for name in ('change.json','verification.json','builder_submission.json','EXECUTION_REPORT.md','REVIEW.md','REVIEW.json',
                 'review_pack.json','candidate.json','BUILD_RECEIPT.json','OWNER_TEST.md','OWNER_TEST.json','test_packet.json',
                 'CONTRACT.md','REFERENCES.json','guard-origin.json','start-fingerprint.json','archive_plan.json','archive_receipt.json'):
        p=source/name
        if p.is_file():refs[p.relative_to(root).as_posix()]=p.read_bytes()
    # Preserve actual evidence bytes, not merely mutable pointers.
    v=source/'verification.json'
    if v.is_file():
        for rec in h.read_json(v).get('checks',{}).values():
            for rel in rec.get('evidence',{}):
                p=h.child(root,rel)
                if p.is_file():refs[rel]=p.read_bytes()
    for rel in c.get('approval_assets',[]):
        p=h.cp(root,c['id'],rel)
        if p.is_file():refs[p.relative_to(root).as_posix()]=p.read_bytes()
    for section in ('assignment','approval'):
        rel=c.get(section,{}).get('owner_record') if isinstance(c.get(section),dict) else None
        if rel:
            p=h.child(root,rel)
            if p.is_file():refs[rel]=p.read_bytes()
    for rel,data in refs.items():h.atomic(h.child(dest,'files/'+rel),data)
    h.write_json(dest/'MANIFEST.json',{'event':event,'at':h.now(),'round':c.get('build_round'),
                                      'files':{r:h.digest(b) for r,b in refs.items()}})
    return dest.relative_to(root).as_posix()

def recover_start(h,root,c,start):
    gr,prefix=repo_info(h,root); tr=tree(h,gr,'HEAD')
    selected={p:tr[prefix+p] for p in start['files'] if prefix+p in tr and tr[prefix+p]['kind']=='blob'}
    bs=blobs(h,gr,[x['oid'] for x in selected.values()])
    recovered={}; missing=[]
    for rel,sha in start['files'].items():
        options=[]; p=h.child(root,rel)
        if p.is_file():options.append(p.read_bytes())
        backup=h.cp(root,c['id'],'recovery/current-at-guard-start/'+rel)
        if backup.is_file():options.append(backup.read_bytes())
        recovered_copy=h.cp(root,c['id'],'recovery/before/'+rel)
        if recovered_copy.is_file():options.append(recovered_copy.read_bytes())
        if rel in selected:options.append(bs[selected[rel]['oid']])
        b=next((v for candidate in options if (v:=match_old_hash(h,candidate,sha)) is not None),None)
        if b is None:missing.append(rel)
        else:recovered[rel]=b
    return recovered,missing

def review_pack(h,root,c):
    o,start,cur,changed=changes(h,root,c); sub=h.submission_ok(root,c)
    recovered,missing=recover_start(h,root,c,start)
    stamp=uid(); path=h.cp(root,c['id'],'reviews/'+stamp); lines=[]
    for rel in changed:
        old=recovered.get(rel,b''); p=h.child(root,rel); new=p.read_bytes() if p.is_file() else b''
        if rel in recovered:h.atomic(h.child(path,'before/'+rel),old)
        if p.is_file():h.atomic(h.child(path,'after/'+rel),new)
        lines.append('\n### '+rel+'\n')
        if rel in missing:lines.append('BEFORE BYTES UNAVAILABLE: recover from original commit/backup; do not declare current file baseline.\n')
        try:
            a=old.decode('utf-8').splitlines(True);b=new.decode('utf-8').splitlines(True)
            lines.extend(difflib.unified_diff(a,b,fromfile='start/'+rel,tofile='current/'+rel))
        except UnicodeDecodeError:lines.append('Binary change; compare hashes and inspect with appropriate tool.\n')
    h.atomic(path/'ACTUAL_DIFF.txt',''.join(lines).encode('utf-8'))
    rec={'schema_version':1,'id':c['id'],'created_at':h.now(),'build_round':c['build_round'],
         'code_fingerprint':cur['sha256'],'approval_sha256':h.approval_ok(root,c),
         'submission_sha256':h.digest(h.canonical(sub)),'start_sha256':o['start_file_sha256'],
         'changed_paths':changed,'missing_start_bytes':missing,'diff_path':(path/'ACTUAL_DIFF.txt').relative_to(root).as_posix(),
         'diff_sha256':h.digest((path/'ACTUAL_DIFF.txt').read_bytes()),'policy_sha256':policy_ok(h,root),
         'last_verified_baseline':o.get('last_verified_baseline'),
         'limits':'Machine checks path/identity only. DLA must review every relevant hunk and real call chain; compile is not UAT.'}
    h.write_json(path/'PACK.json',rec);h.write_json(h.cp(root,c['id'],'review_pack.json'),rec)
    form={'schema_version':1,'id':c['id'],'pack_sha256':h.digest(h.canonical(rec)),'reviewer_role':'DLA',
          'review_session':'TODO separate DLA conversation identifier','builder_session':'TODO DIB conversation identifier',
          'independence':'separate_dla_conversation','decision':'pending','scope_conclusion':'TODO explain actual diff scope',
          'per_file':[{'path':p,'purpose':'TODO','reviewed_hunks':'TODO','within_contract':False} for p in changed],
          'production_journey':'TODO real entry to service to protocol/transport to UI response; old writer handling',
          'preserved_behavior_assessment':'TODO name relevant old behaviors and evidence/remaining tests',
          'baseline_assessment':'TODO last verified version vs task start; state unknown honestly',
          'protocol_assessment':'TODO cite current approved protocol or explain not applicable',
          'risk_level':'normal','fresh_review_required':False,'risk_rationale':'TODO justify risk classification',
          'findings':[],'baseline_gap_owner_record':None,'fresh_review_record':None}
    out=h.cp(root,c['id'],'REVIEW.json')
    if not out.exists():h.write_json(out,form)
    else:h.write_json(path/'REVIEW_FORM.json',form)
    print('Review pack:',(path/'PACK.json').relative_to(root));print('Actual diff:',rec['diff_path'])
    print('REVIEW.json requires substantive DLA decisions; no automatic PASS. Missing original bytes:',missing)
    return rec

def review_report_ok(h,root,c,rel):
    r=h.read_json(h.child(root,rel));p=h.read_json(h.cp(root,c['id'],'review_pack.json'))
    o,start,cur,changed=changes(h,root,c)
    if p.get('code_fingerprint')!=cur['sha256'] or p.get('build_round')!=c['build_round'] or p.get('approval_sha256')!=h.approval_ok(root,c):fail(h,'Review pack stale')
    if p.get('submission_sha256')!=h.digest(h.canonical(h.submission_ok(root,c))):fail(h,'Submission changed after review pack')
    if p.get('diff_sha256')!=h.ev_hash(root,p.get('diff_path')):fail(h,'Actual diff evidence changed')
    if r.get('id')!=c['id'] or r.get('pack_sha256')!=h.digest(h.canonical(p)):fail(h,'REVIEW.json pack binding mismatch')
    if r.get('reviewer_role')!='DLA' or r.get('decision')!='pass':fail(h,'Review must explicitly pass as DLA')
    for k in ('review_session','builder_session','scope_conclusion','production_journey','preserved_behavior_assessment','baseline_assessment','protocol_assessment','risk_rationale'):
        text(h,r.get(k),k)
    if r['review_session']==r['builder_session']:fail(h,'DIB same conversation self-review refused; assertions still not identity authentication')
    if r.get('independence') not in ('separate_dla_conversation','fresh_dla_conversation'):fail(h,'Separate DLA review required')
    rows=r.get('per_file',[])
    if not isinstance(rows,list) or len(rows)!=len(changed) or {x.get('path') for x in rows if isinstance(x,dict)}!=set(changed):fail(h,'Review every actual changed file exactly once')
    for row in rows:
        text(h,row.get('purpose'),'file purpose');text(h,row.get('reviewed_hunks'),'reviewed hunks')
        if row.get('within_contract') is not True:fail(h,'Unresolved semantic scope issue: '+row['path'])
    if not isinstance(r.get('findings'),list):fail(h,'Review findings must be a list')
    for x in r['findings']:
        text(h,x.get('issue'),'finding')
        if x.get('resolution') not in ('fixed','nonblocking_deferred'):fail(h,'Unresolved blocking review finding')
        if x['resolution']=='nonblocking_deferred':h.ev_hash(root,x.get('owner_acceptance_record'))
        text(h,x.get('evidence'),'finding evidence')
    if p.get('missing_start_bytes'):
        h.ev_hash(root,r.get('baseline_gap_owner_record'))
        text(h,r.get('baseline_assessment'),'baseline limitation acceptance',20)
    high=r.get('risk_level')=='high' or r.get('fresh_review_required') is True or c.get('review_policy')=='high_impact'
    if r.get('risk_level') not in ('normal','high'):fail(h,'Risk level must be normal/high')
    if high:
        fresh=h.read_json(h.child(root,r.get('fresh_review_record')))
        if fresh.get('decision')!='pass' or fresh.get('pack_sha256')!=r['pack_sha256']:fail(h,'Fresh high-risk review not bound to this pack')
        text(h,fresh.get('session'),'fresh review session')
        if fresh['session'] in (r['review_session'],r['builder_session']):fail(h,'Fresh reviewer session must be new')
        text(h,fresh.get('analysis'),'fresh review actual analysis',20)
    return r

def review_ok(h,root,c):
    rec=h.check_verification(root,c,'review')
    paths=[r for r in rec.get('evidence',{}) if r.endswith('.json')]
    if not paths:fail(h,'Structured REVIEW.json missing from review evidence')
    good=False;last=None
    for p in paths:
        try:review_report_ok(h,root,c,p);good=True;break
        except (h.HarnessError,OSError,ValueError) as e:last=e
    if not good:fail(h,'No valid actual-diff review: '+str(last))
    return rec

def asset_record(h,root,rel):
    return {'path':rel,'sha256':h.ev_hash(root,rel)}

def normalized_record_paths(h, paths):
    """Canonical Git-relative paths; never mutate signed/historical records.

    Use the existing safe_rel validation before lookup, retaining its path escape
    and absolute-path rejection. No lowercasing, basename match or blob bypass.
    De-duplicate slash/backslash variants only after safe normalization.
    """
    if isinstance(paths, (str, bytes)):
        fail(h, 'Record paths must be a collection, not a single path string')
    return sorted({h.safe_rel(rel).as_posix() for rel in paths})

def closure_assets(h,root,c):
    paths={H+'/changes/'+c['id']+'/'+x for x in c['approval_assets']}
    paths.update(c[x]['owner_record'] for x in ('assignment','approval') if isinstance(c.get(x),dict) and c[x].get('owner_record'))
    base=H+'/changes/'+c['id']+'/'
    for name in ('EXECUTION_REPORT.md','IMPLEMENTATION_RECEIPT.json','builder_submission.json','review_pack.json','REVIEW.json','guard-origin.json','start-fingerprint.json','foreign_acceptance.json','preserved_foreign_inputs.json'):
        if h.child(root,base+name).is_file():paths.add(base+name)
    rp=h.cp(root,c['id'],'review_pack.json')
    if rp.exists():
        pack=h.read_json(rp)
        if pack.get('diff_path'):paths.add(pack['diff_path'])
    rr=h.cp(root,c['id'],'REVIEW.json')
    if rr.exists():
        review=h.read_json(rr)
        for key in ('fresh_review_record','baseline_gap_owner_record'):
            if review.get(key):paths.add(review[key])
        for finding in review.get('findings',[]):
            if finding.get('owner_acceptance_record'):paths.add(finding['owner_acceptance_record'])
    p=h.cp(root,c['id'],'verification.json')
    if p.exists():
        v=h.read_json(p)
        for name in ('review','owner_uat','real_device'):
            for rel in v.get('checks',{}).get(name,{}).get('evidence',{}):paths.add(rel)
    return normalized_record_paths(h, paths)

def verify_saved_files(h,root,rev,paths,compare_current=True):
    paths = normalized_record_paths(h, paths)
    gr,prefix=repo_info(h,root);rev=commit_id(h,root,rev);tr=tree(h,gr,rev)
    missing=[rel for rel in paths if prefix+rel not in tr]
    if missing:fail(h,'RECORD_GIT_SAVE_REQUIRED: '+', '.join(missing[:15]))
    if any(tr[prefix+x]['kind']!='blob' or tr[prefix+x]['mode'] not in ('100644','100755') for x in paths):fail(h,'Record paths must be normal blobs')
    bs=blobs(h,gr,[tr[prefix+x]['oid'] for x in paths])
    if compare_current:
        for rel in paths:
            if not equivalent(h.child(root,rel).read_bytes(),bs[tr[prefix+rel]['oid']]):fail(h,'Committed record differs: '+rel)
    return rev

def ps_quote(s):return "'"+s.replace("'","''")+"'"

def git_plan(h,root,c,archive=False,debug=False):
    changes(h,root,c)
    gr,prefix=repo_info(h,root);cur=fp(h,root);tr=tree(h,gr,'HEAD')
    candidates=set(cur['files'])|{p[len(prefix):] for p in tr if p.startswith(prefix) and product_path(h,p[len(prefix):])}
    bs=blobs(h,gr,[tr[prefix+p]['oid'] for p in candidates if prefix+p in tr and tr[prefix+p]['kind']=='blob'])
    todo=[]
    for rel in sorted(candidates):
        p=h.child(root,rel);x=tr.get(prefix+rel)
        different=(p.is_file() and (not x or x['kind']!='blob' or not equivalent(p.read_bytes(),bs[x['oid']]))) or (not p.exists() and x is not None)
        if different:todo.append(rel)
    allowed=[str(h.safe_rel(x)).rstrip('/') for x in c['allowed_paths']]
    preserved=preserved_foreign_ok(h,root,c)
    scoped_todo=[r for r in todo if r not in preserved]
    inherited=[r for r in scoped_todo if not any(r==a or r.startswith(a+'/') for a in allowed)]
    if inherited:fail(h,'Uncommitted input outside this task scope; classify/preserve separately, no auto include: '+', '.join(inherited))
    records=closure_assets(h,root,c)
    if archive:
        for n in ('verification.json','candidate.json','BUILD_RECEIPT.json','OWNER_TEST.md','OWNER_TEST.json','test_packet.json'):
            p=h.cp(root,c['id'],n)
            if p.exists():records.append(p.relative_to(root).as_posix())
    paths=normalized_record_paths(h, scoped_todo+records);prefix_paths=[prefix+p for p in paths]
    if not paths:fail(h,'No scoped files to save; use existing commit verification')
    out=h.cp(root,c['id'],('ARCHIVE_GIT_PLAN.ps1' if archive else ('SAVEPOINT_GIT_PLAN.ps1' if debug else 'CANDIDATE_GIT_PLAN.ps1')))
    # Emits a plan only. No add/commit/push is executed by this tool.
    command="""# REVIEW before executing. This script stages ONLY listed paths and never commits.
# Stop other writers. Do not execute if the list includes private or unrelated material.
Set-Location -LiteralPath {root}
$existing = @(git -c core.quotePath=false diff --cached --name-only)
if ($LASTEXITCODE -ne 0) {{ throw 'Cannot inspect Git index' }}
if ($existing.Count -gt 0) {{ throw 'Index already contains staged changes. Review them separately; do not auto reset.' }}
$paths = @(
{paths}
)
git --literal-pathspecs add -- $paths
if ($LASTEXITCODE -ne 0) {{ throw 'git add failed; stop and inspect, do not force-add' }}
git diff --cached --check
if ($LASTEXITCODE -ne 0) {{ throw 'Staged whitespace/conflict checks failed' }}
git --no-pager diff --cached --stat
# Inspect actual staged diff, then Owner explicitly runs (not executed here):
# git commit -m '{message}'
# Check $LASTEXITCODE immediately after any Owner-run git commit, before writing evidence.
# An empty staged diff may mean an existing candidate is already saved: inspect/reuse it,
# do not claim that a new commit was created. No empty or duplicate commit is required.
# Record 'created new commit' vs 'reused verified existing commit' truthfully, with full hash.
# Git hooks may run in a user commit. Recheck candidate afterwards; no auto push.
""".format(root=ps_quote(str(gr)),paths=',\n'.join('    '+ps_quote(x) for x in prefix_paths),message=c['id']+(' archive verified internal integration' if archive else (' debug savepoint NOT reviewed or UAT' if debug else ' candidate pending Owner UAT')))
    h.atomic(out,command.encode('utf-8-sig'))
    if archive:
        rec={'id':c['id'],'build_round':c['build_round'],'code_fingerprint':cur['sha256'],'files':{p:h.ev_hash(root,p) for p in records}}
        h.write_json(h.cp(root,c['id'],'archive_plan.json'),rec)
    print('Owner review/stage plan (not executed):',out)
    print('Staging list:',len(paths),'files. Commit only after inspecting staged diff. Re-run check after any hooks.')

def candidate_ok(h,root,c):
    changes(h,root,c);review_ok(h,root,c);preserved_foreign_ok(h,root,c)
    x=h.read_json(h.cp(root,c['id'],'candidate.json'))
    if x.get('code_fingerprint')!=fp(h,root)['sha256'] or x.get('build_round')!=c['build_round'] or x.get('approval_sha256')!=h.approval_ok(root,c):fail(h,'Candidate stale')
    committed_inputs(h,root,x['git']['commit'])
    # Candidate creation verified current records against the commit. Later phase evidence is append-only;
    # do not invalidate the immutable candidate merely because a working-copy report gained build/test notes.
    verify_saved_files(h,root,x['git']['commit'],x['record_paths'],compare_current=False)
    if x.get('owner_record_sha256')!=h.ev_hash(root,x.get('owner_record')):fail(h,'Candidate Owner record changed')
    # Preserved foreign inputs must stay unchanged and must not be introduced by the candidate commit.
    preserved=preserved_foreign_entries(h,root,c)
    if preserved:
        rev=x['git']['commit']; parent=git(h,root,['rev-parse',rev+'^']).decode().strip()
        changed=set(git(h,root,['diff','--name-only',parent,rev]).decode('utf-8','replace').splitlines())
        gr,prefix=repo_info(h,root)
        bad=[r for r in preserved if prefix+r in changed or r in changed]
        if bad: fail(h,'Preserved foreign entered candidate commit: '+', '.join(bad))
    return x

def artifact_files(h,root,paths):
    out={}
    for rel in paths:
        p=h.child(root,rel)
        if p.is_file():out[rel]=h.ev_hash(root,rel)
        elif p.is_dir():
            count=0
            for b,dirs,names in os.walk(p,followlinks=False):
                for d in dirs:
                    if h.linked(Path(b)/d):fail(h,'Linked artifact directory')
                for n in names:
                    q=Path(b)/n;r=q.relative_to(root).as_posix();out[r]=h.ev_hash(root,r);count+=1
            if not count:fail(h,'Empty runtime directory: '+rel)
        else:fail(h,'Missing runnable artifact/dependency: '+rel)
    return out

def build_ok(h,root,c):
    b=h.read_json(h.cp(root,c['id'],'BUILD_RECEIPT.json'))
    if b.get('code_fingerprint')!=fp(h,root)['sha256'] or b.get('build_round')!=c['build_round'] or b.get('approval_sha256')!=h.approval_ok(root,c):fail(h,'Build binding stale')
    if b.get('files')!=artifact_files(h,root,b.get('artifact_roots',[])):fail(h,'Runnable artifacts/dependencies changed after build receipt')
    for r,sha in b.get('logs',{}).items():
        if h.ev_hash(root,r)!=sha:fail(h,'Build log changed')
    if not b.get('files') or not b.get('logs'):fail(h,'Missing runnable/runtime files or build evidence')
    return b

def test_brief_ok(h,root,c):
    r=h.read_json(h.cp(root,c['id'],'OWNER_TEST.json'))
    if r.get('id')!=c['id']:fail(h,'Owner test identity mismatch')
    for k in ('launch_command','working_directory','connection','preconditions','recovery','deliberately_unchanged','result_return'):
        text(h,r.get(k),'OWNER_TEST.'+k)
    if not isinstance(r.get('steps'),list) or not r['steps']:fail(h,'Concrete test steps required')
    for step in r['steps']:
        text(h,step.get('action'),'test action');text(h,step.get('expected'),'test expected result')
    if r.get('device_writes') not in (True,False):fail(h,'Explicit device_writes boolean required')
    return r

def firmware_ok(h,root,c,rel):
    if not c['requirements']['device_related']:return None
    r=h.read_json(h.child(root,rel))
    for k in ('hardware_model','firmware_version','candidate_id','connection','installed_device_confirmation'):
        text(h,r.get(k),'firmware.'+k)
    if r.get('eligible_for_owner_test') is not True:fail(h,'Firmware must be eligible for testing, not merely compiled')
    fw=h.external_root(root,'firmware')
    for k in ('artifact','gate_evidence','protocol_decision'):
        rec=r.get(k,{})
        p=h.child(fw,rec.get('path'))
        if not p.is_file() or h.digest(p.read_bytes())!=rec.get('sha256'):fail(h,'Firmware identity mismatch: '+k)
    return r

def delivery_ok(h,root,c,include_archive=False):
    h.packet_ok(root,c)
    test_brief_ok(h,root,c)
    cand=candidate_ok(h,root,c);b=build_ok(h,root,c)
    packet=h.read_json(h.cp(root,c['id'],'test_packet.json'))
    if packet.get('guard_candidate_sha256')!=h.digest(h.canonical(cand)) or packet.get('guard_build_sha256')!=h.digest(h.canonical(b)):fail(h,'Test packet not bound to reviewed Git candidate/build')
    for name in ('OWNER_TEST.json',):
        if packet.get('guard_brief_sha256')!=h.ev_hash(root,h.cp(root,c['id'],name).relative_to(root).as_posix()):fail(h,'Test instructions changed')
    if c['requirements']['device_related']:firmware_ok(h,root,c,packet['firmware_identity']['path'])
    return packet

def gate_status(h,root,c):
    checks=[('immutable origin / scope / governance',lambda:changes(h,root,c)),
            ('builder submission',lambda:h.submission_ok(root,c)),('actual DLA review',lambda:review_ok(h,root,c)),
            ('Git candidate',lambda:candidate_ok(h,root,c)),('runnable build receipt',lambda:build_ok(h,root,c)),
            ('legacy Owner packet identity (supplemental delivery checks also required)',lambda:delivery_ok(h,root,c))]
    print('Task:',c['id'],'| readiness, not an installation failure')
    for label,fn in checks:
        try:fn();print('PASS:',label)
        except (h.HarnessError,OSError,ValueError,TypeError,KeyError) as e:print('PENDING/BLOCKED:',label,'—',str(e)[:500])
    print('No tests or Git writes executed. Gate status is not product approval.')


def write_transaction(h, items):
    """Best-effort multi-file transaction for Harness records only.
    All validation must occur before calling. Roll back exact previous bytes on any write error.
    """
    old=[]
    for path,data in items:
        old.append((path, path.read_bytes() if path.is_file() else None))
    try:
        for path,data in items:
            h.atomic(path,data)
    except Exception:
        for path,b in reversed(old):
            try:
                if b is None: path.unlink(missing_ok=True)
                else: h.atomic(path,b)
            except Exception:
                pass
        raise

def contract_reconcile(h,root,s,a):
    if a.role!='DLA': fail(h,'contract-reconcile 仅允许 DLA 使用')
    c=h.change(root,a.id)
    if s.get('active_change')!=a.id or s.get('current_assignment')!=a.id:
        fail(h,'仅允许对当前 active change 做 Contract revision reconcile')
    if c.get('status')!='ACTIVE': fail(h,'当前任务不是 ACTIVE，不能做实现中的 Contract revision')
    owner=asset_record(h,root,a.owner_record); reason=asset_record(h,root,a.reason_record)
    start=h.cp(root,a.id,'start-fingerprint.json'); originp=h.cp(root,a.id,'guard-origin.json')
    if not start.is_file() or not originp.is_file(): fail(h,'缺 start-fingerprint/guard-origin；不能凭当前源码重建历史起点')
    old_origin=h.read_json(originp); observed_start=h.digest(start.read_bytes()); expected=old_origin.get('start_file_sha256')
    if observed_start!=expected and not a.repair_origin:
        fail(h,'ORIGINAL_BASELINE_CHANGED：如已由 Owner 明确授权保留当前 start 文件并修复旧 helper 半写，请重跑并显式加 --repair-origin')
    # Validate current Contract/reference/assignment completely BEFORE writing anything.
    old_approval=c.get('approval')
    old_revision=c.get('revision',1)
    newc=json.loads(json.dumps(c))
    newc['revision']=old_revision+1
    newc['contract_revision']={'at':h.now(),'reason_record':reason['path'],'reason_sha256':reason['sha256'],'owner_record':owner['path'],'owner_sha256':owner['sha256'],'previous_revision':old_revision}
    new_inputs=h.contract_inputs(root,newc)
    newc['approval']={'at':h.now(),'owner_record':owner['path'],'owner_record_sha256':owner['sha256'],'inputs':new_inputs,'revision_kind':'owner_approved_contract_revision'}
    newc['phase']='IMPLEMENT'; newc['status']='ACTIVE'; newc['build_round']=int(newc.get('build_round',0))+1
    news=json.loads(json.dumps(s)); news.update(active_change=a.id,current_assignment=a.id,phase='IMPLEMENT',mode='IMPLEMENT',status='active',next_actor='DIB',next_mode='IMPLEMENT')
    news['owner_action']={'required':False,'action':'Owner 已确认本次 Contract revision；DIB 重新 preflight 后按最新 effective Contract 继续实现。'}
    news['test_action']={'required':False,'reason':'仍处实现阶段，尚未形成新的可测候选。'}
    new_origin=json.loads(json.dumps(old_origin))
    repair=None
    if observed_start!=expected:
        repair={'at':h.now(),'old_expected_start_sha256':expected,'observed_start_sha256':observed_start,'owner_record':owner['path'],'owner_sha256':owner['sha256'],'reason_record':reason['path'],'reason_sha256':reason['sha256'],'meaning':'Owner-authorized adoption of the existing start-fingerprint file after legacy helper inconsistency; product files/start file bytes were not changed.'}
        new_origin['start_file_sha256']=observed_start
        new_origin['origin_reconciled_at']=repair['at']
    # Scope check uses the existing start fingerprint and new allowed_paths; no writes yet.
    cur,changed,bad=h.scope_observation(root,newc)
    if bad: fail(h,'Contract revision 后仍存在 allowed_paths 外生产变化：'+', '.join(bad[:20]))
    # Prepare append-only history and all writes in memory first.
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    revp=h.cp(root,a.id,'contract-revisions/'+stamp+'.json')
    rec={'schema_version':1,'id':a.id,'at':h.now(),'from_revision':old_revision,'to_revision':newc['revision'],'reason':reason,'owner':owner,'previous_approval':old_approval,'new_approval':newc['approval'],'origin_repair':repair,'changed_paths_since_start':changed,'scope_outside_contract':bad}
    payloads=[(revp,(json.dumps(rec,ensure_ascii=False,indent=2)+'\n').encode()),(h.cp(root,a.id,'change.json'),(json.dumps(newc,ensure_ascii=False,indent=2)+'\n').encode()),(h.child(root,h.H+'/STATE.json'),(json.dumps({**news,'revision':int(news.get('revision',0))+1,'updated_at':h.now()},ensure_ascii=False,indent=2)+'\n').encode())]
    if repair: payloads.insert(1,(originp,(json.dumps(new_origin,ensure_ascii=False,indent=2)+'\n').encode()))
    write_transaction(h,payloads)
    # Post-write verification. If this fails, transaction already wrote; explicit rollback using old bytes is not available here,
    # so validate the same facts above before writing and only run pure checks now.
    h.approval_ok(root,h.change(root,a.id)); origin(h,root,h.change(root,a.id))
    print('CONTRACT REVISION RECONCILED：历史批准已保留，新 effective approval 已绑定；下一步由 DIB 重新 preflight。')
    if repair: print('ORIGIN REFERENCE RECONCILED：未修改 start-fingerprint/product files；已保存旧/新 hash 与 Owner 授权。')

def base_review_ok_for_preview(h,root,c):
    """Require substantive original DLA review pass, but intentionally do not require high-impact fresh review.
    Preview is non-formal and exists to overlap Owner testing with later governance work.
    """
    p=h.cp(root,c['id'],'REVIEW.json')
    if not p.is_file(): fail(h,'Preview requires DLA REVIEW.json decision=pass')
    r=h.read_json(p); pack=h.read_json(h.cp(root,c['id'],'review_pack.json'))
    if r.get('decision')!='pass' or r.get('reviewer_role')!='DLA': fail(h,'Preview requires original DLA review pass')
    if r.get('pack_sha256')!=h.digest(h.canonical(pack)): fail(h,'Preview review pack binding mismatch')
    # Verify all actual changed files were reviewed and no blocking finding remains.
    changed=pack.get('changed_paths',[]); rows=r.get('per_file',[])
    if {x.get('path') for x in rows if isinstance(x,dict)}!=set(changed): fail(h,'Preview requires review of every changed file')
    if any(x.get('within_contract') is not True for x in rows): fail(h,'Preview blocked by unresolved scope review')
    for finding in r.get('findings',[]):
        if finding.get('resolution') not in ('fixed','nonblocking_deferred'): fail(h,'Preview blocked by review finding')
    return r,pack

def make_preview_snapshot(h,root,c,token):
    dest=h.child(root,H+'/previews/'+c['id']+'/'+token+'/source')
    if dest.exists(): fail(h,'Preview source already exists')
    gr,prefix=repo_info(h,root); tr=tree(h,gr,'HEAD')
    selected={k:v for k,v in tr.items() if k.startswith(prefix) and v['kind']=='blob' and product_path(h,k[len(prefix):])}
    bs=blobs(h,gr,[v['oid'] for v in selected.values()])
    for full,x in selected.items():
        rel=full[len(prefix):]; h.atomic(dest/rel,bs[x['oid']])
    allowed=[str(h.safe_rel(x)).rstrip('/') for x in c['allowed_paths']]
    current=h.source_fingerprint(root)['files']
    # Overlay exactly the task-owned working bytes. Foreign dirty remains at Git HEAD in the snapshot.
    for rel in sorted(current):
        if any(rel==a or rel.startswith(a+'/') for a in allowed):
            src=h.child(root,rel); h.atomic(dest/rel,src.read_bytes())
    # Apply task-owned deletions.
    for full in selected:
        rel=full[len(prefix):]
        if any(rel==a or rel.startswith(a+'/') for a in allowed) and rel not in current:
            (dest/rel).unlink(missing_ok=True)
    snap=h.source_fingerprint(dest)
    return dest,snap

def preview_open(h,root,s,a):
    c=h.require_active(root,s,a.id); basis=preview_basis(h,root,c)
    preserved_foreign_ok(h,root,c)
    token='preview-'+uid(); dest,snap=make_preview_snapshot(h,root,c,token)
    rec={'schema_version':1,'id':a.id,'token':token,'at':h.now(),'status':'build_authorized','preview_only':True,
         'build_round':c['build_round'],'approval_sha256':h.approval_ok(root,c),'basis_kind':basis['kind'],
         'basis_submission_sha256':basis['submission_sha256'],'basis_review_sha256':basis['review_sha256'],'working_code_fingerprint':basis['code_fingerprint'],
         'snapshot_path':dest.relative_to(root).as_posix(),'snapshot_fingerprint':snap['sha256'],
         'preserved_foreign':preserved_foreign_entries(h,root,c),
         'meaning':'OWNER_PREVIEW only. May iterate via PREVIEW_FIX before formal candidate; never implies candidate/release/UAT PASS.'}
    h.write_json(h.child(root,H+'/previews/'+c['id']+'/'+token+'/START.json'),rec)
    h.write_json(h.cp(root,c['id'],'PREVIEW_LATEST.json'),rec)
    print('OWNER PREVIEW BUILD AUTHORIZED:',token)
    print('Build isolated snapshot:',dest)
    print('Formal fresh review/candidate may continue in parallel; preview is not UAT/candidate.')

def preview_finish(h,root,s,a):
    c=h.change(root,a.id); startp=h.child(root,H+'/previews/'+a.id+'/'+a.token+'/START.json'); start=h.read_json(startp)
    if start.get('status')!='build_authorized': fail(h,'Preview token invalid/already finished')
    if start.get('approval_sha256')!=h.approval_ok(root,c) or start.get('build_round')!=c['build_round']: fail(h,'Preview authorization stale')
    text(h,a.command,'preview build command'); text(h,a.entrypoint,'preview runtime entrypoint')
    files=artifact_files(h,root,a.artifact); suffix={'executable':'.exe','jar_classpath':'.jar','classes_classpath':'.class'}[a.runtime_kind]
    if not any(x.lower().endswith(suffix) for x in files): fail(h,'Preview runtime lacks expected '+suffix)
    rec={**start,'status':'ready_for_owner_preview','finished_at':h.now(),'artifact_roots':a.artifact,'files':files,
         'logs':{r:h.ev_hash(root,r) for r in a.log},'command':a.command,'entrypoint':a.entrypoint,'runtime_kind':a.runtime_kind,
         'scope':'OWNER_PREVIEW_ONLY_NOT_FORMAL_UAT'}
    rp=h.child(root,H+'/previews/'+a.id+'/'+a.token+'/PREVIEW_RECEIPT.json'); h.write_json(rp,rec); h.write_json(h.cp(root,a.id,'PREVIEW_LATEST.json'),rec)
    print('OWNER PREVIEW READY:',rp.relative_to(root))
    print('Owner may test now; formal review/candidate/build evidence continues independently.')

def preview_result(h,root,s,a):
    c=h.change(root,a.id); rp=h.child(root,H+'/previews/'+a.id+'/'+a.token+'/PREVIEW_RECEIPT.json'); rec=h.read_json(rp)
    owner=asset_record(h,root,a.owner_record)
    out={'schema_version':1,'id':a.id,'token':a.token,'at':h.now(),'status':a.status,'owner_record':owner['path'],'owner_sha256':owner['sha256'],
         'preview_receipt_sha256':h.digest(h.canonical(rec)),'snapshot_fingerprint':rec['snapshot_fingerprint'],
         'scope':'OWNER_PREVIEW_RESULT_ONLY_NOT_OWNER_UAT'}
    p=h.child(root,H+'/previews/'+a.id+'/'+a.token+'/OWNER_PREVIEW_RESULT.json'); h.write_json(p,out); h.write_json(h.cp(root,a.id,'PREVIEW_RESULT_LATEST.json'),out)
    if a.status=='fail' and s.get('active_change')==a.id:
        s.update(phase='VERIFY',mode='PREVIEW_TRIAGE',status='owner_preview_failed',next_actor='DLA',next_mode='PREVIEW_TRIAGE')
        s['owner_action']={'required':False,'action':'DLA 先判断 Preview FAIL 是实现 Bug、产品语义变化还是协议/架构变化；不要让 Owner 重走完整流程。'}
        s['test_action']={'required':False,'reason':'Preview FAIL 已记录；先分类并路由修复。'}
        h.save_state(root,s)
    print('OWNER PREVIEW',a.status.upper(),'recorded; this is not formal Owner UAT.')

def preview_request_fix(h,root,s,a):
    c=h.require_active(root,s,a.id)
    # Preview feedback is Owner evidence; this path is only for in-contract implementation defects.
    owner=asset_record(h,root,a.owner_record)
    cur,changed,bad=h.scope_observation(root,c)
    if bad: fail(h,'Preview fix has out-of-contract product changes; use DLA CHANGE/Contract revision: '+', '.join(bad[:20]))
    latest=h.cp(root,a.id,'PREVIEW_RESULT_LATEST.json')
    preview=None
    if latest.is_file():
        x=h.read_json(latest)
        if x.get('status')=='fail': preview=x
    n=int(c.get('preview_fix_round',0))+1
    token='preview-fix-'+uid()
    rec={'schema_version':1,'id':a.id,'token':token,'round':n,'at':h.now(),'kind':'implementation_bug',
         'owner_record':owner['path'],'owner_sha256':owner['sha256'],'source_preview':preview,
         'code_fingerprint_before':cur['sha256'],'changed_paths_before':changed,
         'meaning':'Owner Preview in-contract implementation defect. Fast lane: no Product Grill/Contract revision/fresh review/formal candidate required before re-preview.'}
    path=h.child(root,H+'/previews/'+a.id+'/fixes/'+token+'/REQUEST.json');h.write_json(path,rec)
    h.write_json(h.cp(root,a.id,'PREVIEW_FIX_REQUEST_LATEST.json'),rec)
    c['preview_fix_round']=n;c['preview_fix_request']={'path':path.relative_to(root).as_posix(),'sha256':h.ev_hash(root,path.relative_to(root).as_posix())}
    h.save_change(root,c)
    s.update(phase='IMPLEMENT',mode='PREVIEW_FIX',status='preview_fix_requested',next_actor='DIB',next_mode='PREVIEW_FIX')
    s['owner_action']={'required':False,'action':'DIB 只修本次 Owner Preview 的原 Contract 内实现缺陷。'}
    s['test_action']={'required':False,'reason':'修复后走 Preview fix review，再直接重建 Preview 给 Owner。'}
    h.save_state(root,s)
    print('PREVIEW FIX ROUTED:',token,'| next actor DIB | no formal candidate/review reset required now.')


def preview_fix_submit(h,root,s,a):
    h.require_role_mode(s,'DIB','preview-fix-submit')
    c=h.require_active(root,s,a.id)
    if s.get('mode')!='PREVIEW_FIX': fail(h,'preview-fix-submit only allowed in IMPLEMENT/PREVIEW_FIX')
    reqp=h.cp(root,a.id,'PREVIEW_FIX_REQUEST_LATEST.json'); req=h.read_json(reqp)
    cur,changed,bad=h.scope_observation(root,c)
    if bad: fail(h,'Preview fix escaped Contract: '+', '.join(bad[:20]))
    report=asset_record(h,root,a.report)
    evidence=[asset_record(h,root,x) for x in (a.evidence or [])]
    if not evidence: fail(h,'preview-fix-submit requires at least one real machine/check evidence file')
    token=req['token']; path=h.child(root,H+'/previews/'+a.id+'/fixes/'+token+'/SUBMISSION.json')
    if path.exists(): fail(h,'Preview fix already submitted; never overwrite historical round')
    rec={'schema_version':1,'id':a.id,'token':token,'round':req['round'],'at':h.now(),'status':'submitted_for_preview_review',
         'approval_sha256':h.approval_ok(root,c),'code_fingerprint':cur['sha256'],'changed_paths':changed,
         'request_sha256':h.ev_hash(root,reqp.relative_to(root).as_posix()),'report':report,'evidence':evidence,
         'meaning':'Preview-only fix submission. Not formal builder_submission/candidate/UAT.'}
    h.write_json(path,rec);h.write_json(h.cp(root,a.id,'PREVIEW_FIX_LATEST.json'),rec)
    s.update(phase='VERIFY',mode='PREVIEW_FIX_REVIEW',status='preview_fix_submitted',next_actor='DLA',next_mode='PREVIEW_FIX_REVIEW')
    s['owner_action']={'required':False,'action':'DLA 只审本轮 Preview fix；通过后直接重建 Preview。'}
    s['test_action']={'required':False,'reason':'尚未生成下一轮 Preview artifact。'}
    h.save_state(root,s)
    print('PREVIEW FIX SUBMITTED:',token,'| next actor DLA preview-fix-review.')


def preview_fix_review(h,root,s,a):
    if a.role!='DLA': fail(h,'preview-fix-review only DLA')
    c=h.require_active(root,s,a.id)
    if s.get('mode')!='PREVIEW_FIX_REVIEW': fail(h,'preview-fix-review only allowed in VERIFY/PREVIEW_FIX_REVIEW')
    sub=h.read_json(h.cp(root,a.id,'PREVIEW_FIX_LATEST.json'))
    cur=h.scope_diff(root,c)
    if sub.get('code_fingerprint')!=cur['sha256'] or sub.get('approval_sha256')!=h.approval_ok(root,c): fail(h,'Preview fix submission stale')
    review=asset_record(h,root,a.review_record)
    path=h.child(root,H+'/previews/'+a.id+'/fixes/'+sub['token']+'/REVIEW.json')
    rec={'schema_version':1,'id':a.id,'token':sub['token'],'round':sub['round'],'at':h.now(),'status':a.status,
         'review_record':review['path'],'review_sha256':review['sha256'],'code_fingerprint':cur['sha256'],
         'submission_sha256':h.digest(h.canonical(sub)),'scope':'PREVIEW_FIX_REVIEW_ONLY_NOT_FORMAL_REVIEW'}
    h.write_json(path,rec)
    if a.status=='pass':
        latest={**sub,'status':'review_pass','review_record':review['path'],'review_sha256':review['sha256'],'review_receipt':path.relative_to(root).as_posix()}
        h.write_json(h.cp(root,a.id,'PREVIEW_FIX_LATEST.json'),latest)
        s.update(phase='VERIFY',mode='PREVIEW_REBUILD',status='preview_fix_review_pass',next_actor='DLA',next_mode='PREVIEW_REBUILD')
        s['owner_action']={'required':False,'action':'DLA 可直接 preview-open；无需 fresh review/candidate 后才能让 Owner 再测。'}
        s['test_action']={'required':False,'reason':'等待下一轮 Preview build。'}
        print('PREVIEW FIX REVIEW PASS; open a new Preview build now.')
    else:
        s.update(phase='IMPLEMENT',mode='PREVIEW_FIX',status='preview_fix_review_fail',next_actor='DIB',next_mode='PREVIEW_FIX')
        s['owner_action']={'required':False,'action':'DIB 继续修同一 Preview defect；不扩大范围。'}
        s['test_action']={'required':False,'reason':'Preview fix review fail；修复后再次提交。'}
        print('PREVIEW FIX REVIEW FAIL; returned to DIB PREVIEW_FIX.')
    h.save_state(root,s)


def preview_basis(h,root,c):
    p=h.cp(root,c['id'],'PREVIEW_FIX_LATEST.json')
    if p.is_file():
        x=h.read_json(p); cur=h.scope_diff(root,c)
        if x.get('status')=='review_pass' and x.get('code_fingerprint')==cur['sha256'] and x.get('approval_sha256')==h.approval_ok(root,c):
            return {'kind':'preview_fix_review','code_fingerprint':cur['sha256'],'submission_sha256':h.digest(h.canonical(x)),'review_sha256':x.get('review_sha256'),'build_round':c['build_round']}
    sub=h.submission_ok(root,c); review,pack=base_review_ok_for_preview(h,root,c)
    return {'kind':'formal_review','code_fingerprint':sub['code_fingerprint'],'submission_sha256':h.digest(h.canonical(sub)),'review_sha256':h.digest(h.canonical(pack)),'build_round':c['build_round']}

def preview_status(h,root,c):
    p=h.cp(root,c['id'],'PREVIEW_LATEST.json')
    if not p.is_file(): print('Owner preview: NONE'); return
    x=h.read_json(p); print('Owner preview:',x.get('status'),'| token:',x.get('token'),'| snapshot:',x.get('snapshot_fingerprint'))
    rr=h.cp(root,c['id'],'PREVIEW_RESULT_LATEST.json')
    if rr.is_file(): print('Owner preview result:',h.read_json(rr).get('status'),'| formal owner_uat remains separate')

def make_parser(h):
    p=h.legacy_parser(); sub=next(a for a in p._actions if isinstance(a,argparse._SubParsersAction))
    for name in ('guard-status','review-pack','candidate-plan','archive-plan','savepoint-plan'):
        q=sub.add_parser(name);q.add_argument('--id',required=True);q.add_argument('--role',choices=['DLA'],default='DLA')
    q=sub.add_parser('baseline-start');q.add_argument('--id',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('candidate-check');q.add_argument('--id',required=True);q.add_argument('--commit',default='HEAD');q.add_argument('--owner-record',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('archive-check');q.add_argument('--id',required=True);q.add_argument('--commit',default='HEAD');q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('request-build');q.add_argument('--id',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('build-open');q.add_argument('--id',required=True);q.add_argument('--role',choices=['DIB'],required=True)
    q=sub.add_parser('build-finish');q.add_argument('--id',required=True);q.add_argument('--token',required=True);q.add_argument('--artifact',action='append',required=True);q.add_argument('--log',action='append',required=True);q.add_argument('--command',required=True);q.add_argument('--entrypoint',required=True);q.add_argument('--runtime-kind',choices=['executable','jar_classpath','classes_classpath'],required=True);q.add_argument('--role',choices=['DIB'],required=True)
    q=sub.add_parser('reconcile-foreign');q.add_argument('--id',required=True);q.add_argument('--owner-record',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('recover-start');q.add_argument('--id',required=True);q.add_argument('--commit',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('contract-reconcile');q.add_argument('--id',required=True);q.add_argument('--owner-record',required=True);q.add_argument('--reason-record',required=True);q.add_argument('--repair-origin',action='store_true');q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('candidate-preserve-foreign');q.add_argument('--id',required=True);q.add_argument('--path',action='append',required=True);q.add_argument('--owner-record',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('preview-open');q.add_argument('--id',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('preview-finish');q.add_argument('--id',required=True);q.add_argument('--token',required=True);q.add_argument('--artifact',action='append',required=True);q.add_argument('--log',action='append',required=True);q.add_argument('--command',required=True);q.add_argument('--entrypoint',required=True);q.add_argument('--runtime-kind',choices=['executable','jar_classpath','classes_classpath'],required=True);q.add_argument('--role',choices=['DIB'],required=True)
    q=sub.add_parser('preview-result');q.add_argument('--id',required=True);q.add_argument('--token',required=True);q.add_argument('--status',choices=['pass','fail'],required=True);q.add_argument('--owner-record',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('preview-request-fix');q.add_argument('--id',required=True);q.add_argument('--owner-record',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('preview-fix-submit');q.add_argument('--id',required=True);q.add_argument('--report',required=True);q.add_argument('--evidence',action='append');q.add_argument('--role',choices=['DIB'],required=True)
    q=sub.add_parser('preview-fix-review');q.add_argument('--id',required=True);q.add_argument('--status',choices=['pass','fail'],required=True);q.add_argument('--review-record',required=True);q.add_argument('--role',choices=['DLA'],required=True)
    q=sub.add_parser('preview-status');q.add_argument('--id',required=True);q.add_argument('--role',choices=['DLA'],default='DLA')
    return p

def run(h,argv=None):
    a=h.parser().parse_args(argv);root=Path(a.repo).expanduser().resolve() if a.repo else Path(h.__file__).resolve().parents[4]
    s=h.state(root)
    if a.cmd in ('doctor','status','validate','fingerprint','prompt','preflight'):
        if a.cmd!='fingerprint':policy_ok(h,root)
        if a.cmd=='preflight' and a.role=='DIB':
            h.require_role_mode(s,'DIB','preflight');origin(h,root,h.require_active(root,s,a.id))
        result=h.legacy_main(argv)
        if a.cmd in ('status','validate') and s.get('active_change'):
            print('Delivery guards are separate: run guard-status --id '+s['active_change']+'. Missing review/Git/build is NOT upgrade failure.')
        return result
    if a.cmd=='guard-status':
        policy_ok(h,root);gate_status(h,root,h.change(root,a.id));return 0
    if a.cmd=='preview-status':
        policy_ok(h,root);preview_status(h,root,h.change(root,a.id));return 0
    if a.cmd=='candidate-preserve-foreign':
        with h.lock(root):
            c=h.require_active(root,s,a.id); candidate_preserve_foreign(h,root,c,a.path,a.owner_record)
        return 0
    if a.cmd=='preview-open':
        policy_ok(h,root)
        with h.lock(root): preview_open(h,root,s,a)
        return 0
    if a.cmd=='preview-finish':
        policy_ok(h,root)
        with h.lock(root): preview_finish(h,root,s,a)
        return 0
    if a.cmd=='preview-result':
        policy_ok(h,root)
        with h.lock(root): preview_result(h,root,s,a)
        return 0
    if a.cmd=='preview-request-fix':
        policy_ok(h,root)
        with h.lock(root): preview_request_fix(h,root,s,a)
        return 0
    if a.cmd=='preview-fix-submit':
        policy_ok(h,root)
        with h.lock(root): preview_fix_submit(h,root,s,a)
        return 0
    if a.cmd=='preview-fix-review':
        policy_ok(h,root)
        with h.lock(root): preview_fix_review(h,root,s,a)
        return 0
    policy_ok(h,root)
    if a.cmd=='contract-reconcile':
        with h.lock(root):
            contract_reconcile(h,root,s,a)
        return 0
    if a.cmd=='reconcile-foreign':
        with h.lock(root):
            c=h.change(root,a.id);o=h.read_json(h.cp(root,a.id,'guard-origin.json'))
            if o.get('start_file_sha256')!=h.ev_hash(root,H+'/changes/'+a.id+'/start-fingerprint.json'):fail(h,'Original baseline altered')
            owner=asset_record(h,root,a.owner_record)
            history(h,root,c,'before-foreign-reconcile')
            h.write_json(h.cp(root,a.id,'foreign_acceptance.json'),{'at':h.now(),'owner_record':owner['path'],'owner_sha256':owner['sha256'],
                          'accepted_snapshot':foreign_snapshot(h,root),'meaning':'Owner recorded unrelated sibling work; no file reverted or silently granted to DIB.'})
            print('Sibling work attribution recorded; original task origin retained.')
        return 0
    if a.cmd=='recover-start':
        with h.lock(root):
            c=h.change(root,a.id);start=h.read_json(h.cp(root,a.id,'start-fingerprint.json'));gr,prefix=repo_info(h,root)
            rev=commit_id(h,root,a.commit);tr=tree(h,gr,rev)
            selected={rel:tr[prefix+rel] for rel in start['files'] if prefix+rel in tr and tr[prefix+rel]['kind']=='blob'}
            bs=blobs(h,gr,[x['oid'] for x in selected.values()]);count=0
            for rel,x in selected.items():
                b=match_old_hash(h,bs[x['oid']],start['files'][rel])
                if b is not None:h.atomic(h.cp(root,a.id,'recovery/before/'+rel),b);count+=1
            print('Recovered matching original bytes from',rev,':',count,'files. No baseline hash or product file changed.')
        return 0
    if a.cmd=='baseline-start':
        with h.lock(root):
            c=h.change(root,a.id)
            if c.get('status')!='DRAFT' or c.get('approval'):fail(h,'Start baseline only on unapproved dispatched draft')
            anchor=committed_inputs(h,root)
            p=h.cp(root,a.id,'start-fingerprint.json')
            if not p.exists():h.write_json(p,fp(h,root))
            make_origin(h,root,c,'pre_implementation')
            h.write_json(h.cp(root,a.id,'START_GIT.json'),anchor)
            print('Recoverable start recorded; no approval or implementation. Last verified baseline may remain UNKNOWN.')
        return 0
    if a.cmd=='request-build':
        with h.lock(root):
            c=h.require_active(root,s,a.id);review_ok(h,root,c);candidate_ok(h,root,c)
            s.update(phase='VERIFY',mode='BUILD_ONLY',status='build_only_requested',next_actor='DIB',next_mode='BUILD_ONLY')
            s['owner_action']={'required':False,'action':'DIB仅补当前候选的构建/打包证据，不改功能范围。'}
            s['test_action']={'required':False,'reason':'构建后仍需DLA核对产物身份，再决定Owner测试。'}
            h.save_state(root,s);print('BUILD_ONLY routed to DIB for reviewed Git candidate; no build executed by Harness.')
        return 0
    newcmds=('review-pack','candidate-plan','candidate-check','archive-plan','archive-check','build-open','build-finish','savepoint-plan')
    if a.cmd in newcmds:
        with h.lock(root):
            c=h.require_active(root,s,a.id)
            if a.cmd in ('build-open','build-finish'): h.require_role_mode(s,'DIB',a.cmd)
            changes(h,root,c)
            if a.cmd=='review-pack':history(h,root,c,'before-review-pack');review_pack(h,root,c)
            elif a.cmd in ('candidate-plan','archive-plan','savepoint-plan'):
                if a.cmd!='savepoint-plan':review_ok(h,root,c)
                if a.cmd=='archive-plan':
                    delivery_ok(h,root,c)
                    for name in h.CHECKS:h.check_verification(root,c,name)
                git_plan(h,root,c,a.cmd=='archive-plan',a.cmd=='savepoint-plan')
            elif a.cmd=='candidate-check':
                review_ok(h,root,c);anchor=committed_inputs(h,root,a.commit)
                records=closure_assets(h,root,c);verify_saved_files(h,root,anchor['commit'],records)
                owner=asset_record(h,root,a.owner_record)
                history(h,root,c,'before-candidate')
                preserved=preserved_foreign_ok(h,root,c)
                if preserved:
                    rev=anchor['commit']; parent=git(h,root,['rev-parse',rev+'^']).decode().strip()
                    changed=set(git(h,root,['diff','--name-only',parent,rev]).decode('utf-8','replace').splitlines())
                    gr,prefix=repo_info(h,root)
                    bad=[r for r in preserved if prefix+r in changed or r in changed]
                    if bad: fail(h,'Preserved foreign entered candidate commit: '+', '.join(bad))
                x={'id':a.id,'at':h.now(),'build_round':c['build_round'],'code_fingerprint':fp(h,root)['sha256'],
                   'approval_sha256':h.approval_ok(root,c),'git':anchor,'record_paths':records,
                   'preserved_foreign':preserved,
                   'owner_record':owner['path'],'owner_record_sha256':owner['sha256'],'scope':'candidate_pending_owner_uat_not_release'}
                h.write_json(h.cp(root,a.id,'candidate.json'),x);print('GIT CANDIDATE PASS; not UAT. No Git write was executed.')
            elif a.cmd=='build-open':
                candidate_ok(h,root,c)
                # DIB may build, but this helper only captures evidence and never runs product commands.
                token=uid();rec={'id':a.id,'token':token,'at':h.now(),'code_fingerprint':fp(h,root)['sha256'],
                 'approval_sha256':h.approval_ok(root,c),'build_round':c['build_round']}
                h.write_json(h.cp(root,a.id,'builds/'+token+'/START.json'),rec);print('BUILD TOKEN:',token,'; run authorized build separately, then build-finish.')
            elif a.cmd=='build-finish':
                if not re.fullmatch(r'[A-Za-z0-9-]+',a.token):fail(h,'Invalid build token')
                start=h.read_json(h.cp(root,a.id,'builds/'+a.token+'/START.json'))
                if start['code_fingerprint']!=fp(h,root)['sha256'] or start['approval_sha256']!=h.approval_ok(root,c) or start['build_round']!=c['build_round']:fail(h,'Inputs changed during build; repeat after inspecting changes')
                receipt=h.cp(root,a.id,'builds/'+a.token+'/RECEIPT.json')
                if receipt.exists():fail(h,'Build token already finished; never overwrite historical receipt')
                text(h,a.command,'actual build command');text(h,a.entrypoint,'runtime entrypoint')
                files=artifact_files(h,root,a.artifact)
                suffix={'executable':'.exe','jar_classpath':'.jar','classes_classpath':'.class'}[a.runtime_kind]
                if not any(r.lower().endswith(suffix) for r in files):fail(h,'Runtime manifest lacks expected '+suffix+' file; compile log or Markdown is not a runnable output')
                cand=candidate_ok(h,root,c)
                rec={**start,'finished_at':h.now(),'artifact_roots':a.artifact,'files':files,'logs':{r:h.ev_hash(root,r) for r in a.log},
                    'candidate_commit':cand['git']['commit'],'command':a.command,'entrypoint':a.entrypoint,'runtime_kind':a.runtime_kind,
                    'limits':'Binds declared candidate/build logs/outputs; does not prove launch, UI, Firmware, or UAT.'}
                report_path=h.cp(root,a.id,'builds/'+a.token+'/BUILD_REPORT.md')
                report_text='# Build Report — '+a.id+'\n\n- token: `'+a.token+'`\n- candidate: `'+cand['git']['commit']+'`\n- command: `'+a.command+'`\n- entrypoint: `'+a.entrypoint+'`\n- runtime_kind: `'+a.runtime_kind+'`\n\nBuild evidence is append-only and MUST NOT be appended to EXECUTION_REPORT.md.\n'
                history(h,root,c,'before-build-receipt');h.atomic(report_path,report_text.encode('utf-8'));rec['build_report']=report_path.relative_to(root).as_posix();rec['build_report_sha256']=h.digest(report_path.read_bytes());h.write_json(receipt,rec);h.write_json(h.cp(root,a.id,'BUILD_RECEIPT.json'),rec)
                print('Build receipt recorded in phase-scoped build evidence; do not append to EXECUTION_REPORT.md.')
            elif a.cmd=='archive-check':
                delivery_ok(h,root,c)
                for name in h.CHECKS:h.check_verification(root,c,name)
                plan=h.read_json(h.cp(root,a.id,'archive_plan.json'))
                if plan.get('code_fingerprint')!=fp(h,root)['sha256'] or plan.get('build_round')!=c['build_round']:fail(h,'Archive plan stale')
                for r,sha in plan['files'].items():
                    if h.ev_hash(root,r)!=sha:fail(h,'Archive input changed; rerun archive-plan: '+r)
                rev=verify_saved_files(h,root,a.commit,list(plan['files']))
                h.write_json(h.cp(root,a.id,'archive_receipt.json'),{'commit':rev,'plan_sha256':h.digest(h.canonical(plan)),'at':h.now()})
                print('Result archive verified; close may now record bookkeeping without recursive commit gate.')
            # Persist the next responsible actor; a report must not silently wait without a Git prompt.
            if a.cmd in ('candidate-plan','archive-plan','savepoint-plan'):
                plan_name={'candidate-plan':'CANDIDATE_GIT_PLAN.ps1','archive-plan':'ARCHIVE_GIT_PLAN.ps1','savepoint-plan':'SAVEPOINT_GIT_PLAN.ps1'}[a.cmd]
                s.update(phase='VERIFY',mode={'candidate-plan':'CANDIDATE_GIT','archive-plan':'RESULT_GIT','savepoint-plan':'SAVEPOINT_GIT'}[a.cmd],next_actor='Owner',next_mode='GIT_SAVE')
                s['owner_action']={'required':True,'action':'先审查本项 '+plan_name+' 的精确清单，暂存后检查diff，由Owner执行commit；Agent不自动Git写。'}
                s['test_action']={'required':False,'reason':'候选或结果存档中；不是新测试任务。'}
            elif a.cmd=='build-open':
                s.update(phase='VERIFY',mode='BUILD_ONLY',next_actor='DIB',next_mode='BUILD_ONLY')
                s['owner_action']={'required':False,'action':'DIB执行已授权的构建/打包，记录真实日志和全部运行依赖。'}
                s['test_action']={'required':False,'reason':'准备运行产物，尚未交测。'}
            elif a.cmd in ('candidate-check','build-finish','archive-check','review-pack'):
                s.update(phase='VERIFY',mode='DLA_REVIEW' if a.cmd=='review-pack' else 'DELIVERY_PREP',next_actor='DLA',next_mode='REVIEW' if a.cmd=='review-pack' else 'DELIVERY_PREP')
                s['owner_action']={'required':False,'action':'DLA继续核对实际审阅、候选、产物和测试交接，不重复产品审批。'}
                s['test_action']={'required':False,'reason':'尚未发出新的完整Owner测试包。'}
            h.save_state(root,s)
        return 0
    cid=getattr(a,'id',None);c=h.change(root,cid) if cid and h.cp(root,cid,'change.json').exists() else None
    if a.cmd in ('approve','activate'):
        if a.cmd=='approve' and not h.cp(root,a.id,'guard-origin.json').exists():fail(h,'Run baseline-start after preserving current source in Git, before first approval')
        origin(h,root,c)
        if a.cmd=='activate':
            # Do not replace initial fingerprint; compare cumulative range on resume.
            h.scope_diff(root,c)
        if a.cmd=='approve' and not c.get('build_round'):committed_inputs(h,root)
    fact_fail = bool(c and a.cmd=='record-check' and a.check in ('real_device','owner_uat') and a.status=='fail')
    preserve_without_scope_gate = bool(c and a.cmd in ('reopen-contract','suspend'))
    if c and c.get('status')=='ACTIVE' and not (fact_fail or preserve_without_scope_gate):
        changes(h,root,c)
    if a.cmd=='record-check' and a.check=='review' and a.status=='pass':
        if a.role!='DLA':fail(h,'Only DLA records review')
        reports=[r for r in a.evidence if r.endswith('.json')]
        if not reports:fail(h,'Actual structured REVIEW.json required; Markdown/template presence is insufficient')
        for r in reports:review_report_ok(h,root,c,r)
    if a.cmd=='request-test':
        cand=candidate_ok(h,root,c);b=build_ok(h,root,c);test_brief_ok(h,root,c)
        receipt_rel=H+'/changes/'+a.id+'/BUILD_RECEIPT.json'
        if a.artifact!=receipt_rel and a.artifact not in b['files']:fail(h,'--artifact must be a manifested runtime file or BUILD_RECEIPT.json; no random document as runnable artifact')
        if c['requirements']['device_related']:
            if not a.firmware_record:fail(h,'Structured Firmware identity required')
            firmware_ok(h,root,c,a.firmware_record)
    if a.cmd=='record-check' and a.check in ('real_device','owner_uat') and a.status=='pass':delivery_ok(h,root,c)
    if a.cmd=='suspend':
        # Debug savepoint may be committed without passing review/UAT; never label it accepted.
        committed_inputs(h,root)
    if a.cmd=='close':
        delivery_ok(h,root,c)
        plan=h.read_json(h.cp(root,a.id,'archive_plan.json'));ar=h.read_json(h.cp(root,a.id,'archive_receipt.json'))
        if ar.get('plan_sha256')!=h.digest(h.canonical(plan)):fail(h,'Result archive not verified')
        for r,sha in plan['files'].items():
            if h.ev_hash(root,r)!=sha:fail(h,'Result changed since archive')
        verify_saved_files(h,root,ar['commit'],list(plan['files']))
    if c and a.cmd in ('approve','activate','submit','record-check','request-test','request-fix','reopen-contract','suspend','park','close'):
        # The legacy engine also acquires its writer lock; archive first under the same cooperative lock.
        with h.lock(root):history(h,root,c,'before-'+a.cmd)
    result=h.legacy_main(argv)
    if result==0 and c:
        with h.lock(root):
            c=h.change(root,cid);s=h.state(root)
            if a.cmd=='submit':
                s.update(mode='DLA_REVIEW',next_actor='DLA',next_mode='REVIEW',status='awaiting_actual_diff_review')
                s['owner_action']={'required':False,'action':'DLA 审阅真实累计差异；随后提示候选 Git 操作，不直接交真机。'}
                h.save_state(root,s)
            if a.cmd=='record-check' and a.check=='review' and a.status=='pass':
                s.update(mode='CANDIDATE_PREP',next_actor='DLA',next_mode='CANDIDATE_PREP')
                s['owner_action']={'required':False,'action':'DLA生成并审查精确Git候选计划，然后明确提示Owner存档。'}
                s['test_action']={'required':False,'reason':'审阅通过仍需Git候选和可运行产物绑定。'}
                h.save_state(root,s)
            if a.cmd=='request-test':
                packet=h.read_json(h.cp(root,cid,'test_packet.json'))
                packet.update(guard_candidate_sha256=h.digest(h.canonical(cand)),guard_build_sha256=h.digest(h.canonical(b)),
                              guard_brief_sha256=h.ev_hash(root,H+'/changes/'+cid+'/OWNER_TEST.json'))
                h.write_json(h.cp(root,cid,'test_packet.json'),packet)
            history(h,root,c,'after-'+a.cmd)
            if a.cmd=='close':
                packet=h.read_json(h.cp(root,cid,'test_packet.json'))
                h.write_json(h.child(root,H+'/VERIFIED_BASELINE.json'),{'id':cid,'at':h.now(),
                     'candidate':h.read_json(h.cp(root,cid,'candidate.json')),'test_packet':packet,
                     'accepted_scope':c['title'],'preserved_behaviors':c['preserved_behaviors'],
                     'limitations':'Only this task and explicitly tested paths; not whole-product or all firmware compatibility validation.'})
    return result
