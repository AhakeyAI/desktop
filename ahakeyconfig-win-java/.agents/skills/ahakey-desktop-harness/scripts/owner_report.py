#!/usr/bin/env python3
"""v1.2 Owner-facing Chinese report renderer. Progress output is optional; no project/state writes."""
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path, PureWindowsPath
from typing import Any
class ReportError(ValueError): pass
CJK=re.compile(r'[\u3400-\u9fff]')

def text(v:Any,name:str)->str:
    if not isinstance(v,str) or not v.strip(): raise ReportError(f'{name}: 必须给具体文本，不能留空')
    v=v.strip()
    if any(x in v for x in ('```','~~~','\x00')) or re.search(r'\b(?:TODO|TBD)\b|待填写|\{\{',v,re.I): raise ReportError(f'{name}: 不接受占位内容或嵌套代码围栏')
    return v

def narrative(v:Any,name:str)->str:
    v=text(v,name)
    # Long owner-facing prose must contain Chinese. Paths/commands/status-only short strings remain allowed.
    if len(v)>=28 and len(CJK.findall(v))<3:
        raise ReportError(f'{name}: 面向 Owner 的长叙述必须用中文；英文错误/代码请先中文解释再附原文')
    if len(v)>1200: raise ReportError(f'{name}: 过长；请先用中文概括，细节放证据/Prompt')
    return v

def rows(v:Any,name:str,minimum:int=0,narr=True)->list[str]:
    if not isinstance(v,list) or len(v)<minimum: raise ReportError(f'{name}: 必须为至少 {minimum} 项的列表')
    if len(v)>12: raise ReportError(f'{name}: 面向 Owner 列表过长，请归并为不超过12项')
    fn=narrative if narr else text
    return [fn(x,f'{name}[{i}]') for i,x in enumerate(v)]

def obj(v:Any,name:str)->dict:
    if not isinstance(v,dict): raise ReportError(f'{name}: 必须为对象')
    return v

def path_text(v:Any,name:str)->str:
    v=text(v,name)
    if '\n' in v or '\r' in v or not (PureWindowsPath(v).is_absolute() or Path(v).is_absolute()): raise ReportError(f'{name}: 必须为完整绝对路径')
    return v

def validate(d:Any)->dict:
    d=obj(d,'input')
    if d.get('schema_version')!=1: raise ReportError('schema_version 必须为 1')
    p=obj(d.get('progress'),'progress'); narrative(p.get('position'),'progress.position'); narrative(p.get('conclusion'),'progress.conclusion')
    rows(d.get('completed'),'completed',1); rows(d.get('remaining'),'remaining')
    owner=obj(d.get('owner'),'owner')
    for k in ('decision','operation','test'):
        a=obj(owner.get(k),'owner.'+k)
        if type(a.get('required')) is not bool: raise ReportError('owner.'+k+'.required 必须为布尔值')
        narrative(a.get('action'),'owner.'+k+'.action')
    test=owner['test']
    if test['required']:
        rows(test.get('prerequisites'),'owner.test.prerequisites',1)
        st=test.get('steps')
        if not isinstance(st,list) or not st: raise ReportError('需要 Owner 测试时必须直接给 steps')
        for i,s in enumerate(st):
            s=obj(s,'step'); narrative(s.get('action'),f'steps[{i}].action'); narrative(s.get('expected'),f'steps[{i}].expected')
        narrative(test.get('stop_recovery'),'owner.test.stop_recovery'); narrative(test.get('feedback'),'owner.test.feedback')
    n=obj(d.get('next'),'next')
    if n.get('role') not in ('DLA','DIB'): raise ReportError('next.role 必须为 DLA 或 DIB')
    if n.get('destination') not in ('原 DLA 对话','独立 DLA 审阅对话','DIB 对话','当前对话','等待 Owner 后恢复 DLA'): raise ReportError('next.destination 必须指明实际接收窗口')
    if n['role']=='DIB' and n['destination'] not in ('DIB 对话','当前对话'): raise ReportError('DIB 角色与目标窗口不一致')
    if n['role']=='DLA' and n['destination']=='DIB 对话': raise ReportError('DLA 不能接到 DIB 窗口')
    if n['destination'] in ('原 DLA 对话','独立 DLA 审阅对话','DIB 对话') and not owner['operation']['required']: raise ReportError('跨对话复制提示词是 Owner 操作，operation.required 不能为 false')
    text(n.get('mode'),'next.mode'); text(n.get('task'),'next.task'); narrative(n.get('action'),'next.action'); narrative(n.get('authorization'),'next.authorization'); narrative(n.get('goal'),'next.goal')
    path_text(n.get('repo'),'next.repo')
    rows(n.get('facts'),'next.facts',1); rows(n.get('read'),'next.read',1,narr=False); rows(n.get('allowed'),'next.allowed',1); rows(n.get('forbidden'),'next.forbidden',1)
    for v in n['read']: path_text(v,'next.read')
    rows(d.get('evidence',[]),'evidence',narr=False)
    return d

def render(data:Any)->str:
    d=validate(data);p=d['progress'];o=d['owner'];n=d['next']
    lines=['## 1. 当前进度与结论','',p['conclusion'],'','当前位置：'+p['position'],'','## 2. 上一步完成了什么，还差什么','']
    lines += ['- '+v for v in d['completed']]
    lines += ['','尚未完成：'] + (['- '+v for v in d['remaining']] if d['remaining'] else ['本轮范围内没有列出的未完成项；这不自动扩大验收范围。'])
    lines += ['','## 3. 你现在需要做什么','']
    for k,label in [('decision','产品／范围决策'),('operation','操作（含复制提示词／切换对话）'),('test','实际测试')]:
        a=o[k]; lines += [f'**{label}：'+('需要。' if a['required'] else '不需要。')+'** '+a['action'],'']
    if o['test']['required']:
        t=o['test']; lines += ['测试前置：']+['- '+v for v in t['prerequisites']]+['','具体步骤：']
        for i,s in enumerate(t['steps'],1): lines += [f"{i}. {s['action']}\n   预期：{s['expected']}"]
        lines += ['','停止与恢复：'+t['stop_recovery'],'反馈方式：'+t['feedback'],'']
    lines += ['## 4. 下一步交给谁','',f"{n['destination']}／{n['role']}／{n['mode']}／{n['task']}",n['action'],'','## 5. 可直接复制的下一步提示词','',f"复制到：**{n['destination']}**。" if n['destination'] not in ('当前对话','等待 Owner 后恢复 DLA') else '以下用于后续恢复；不需要现在创建新任务或重复发送。','','```text','$ahakey-desktop-lead' if n['role']=='DLA' else '$ahakey-desktop-builder','$ahakey-desktop-harness','',f"角色：{n['role']}；目标窗口：{n['destination']}",'工作目录：'+n['repo'],'任务：'+n['task'],'本轮模式：'+n['mode'],'','事实与接续位置：']
    lines += ['- '+v for v in n['facts']]
    lines += ['','先读取适用 AGENTS.md、当前角色及公共 Harness Skill，随后读取：']+['- '+v for v in n['read']]
    lines += ['','授权依据与边界：'+n['authorization'],'本轮目标：'+n['goal'],'','允许：']+['- '+v for v in n['allowed']]
    lines += ['','禁止：']+['- '+v for v in n['forbidden']]
    lines += ['','所有面向 Owner 的自然语言默认中文；路径、命令、类名和协议字段可保留英文。','不要求定时心跳；仅在 blocker、Owner 决策或阶段切换等有意义节点主动汇报。','需要下一次接力时，在当前聊天正文完整给出 Prompt，不能只说“提示词见文件”。','```']
    if d.get('evidence'): lines += ['','归档依据（正文已给行动，不必为取得提示词打开文件）：']+['- '+v for v in d['evidence']]
    return '\n'.join(lines)+'\n'

def progress(data:Any)->str:
    d=obj(data,'input'); pos=narrative(d.get('position'),'position'); done=narrative(d.get('done'),'done'); nxt=narrative(d.get('next'),'next')
    need=d.get('owner_needed')
    if type(need) is not bool: raise ReportError('owner_needed 必须为布尔值')
    owner=narrative(d.get('owner_action'),'owner_action') if need else '暂时不需要你操作，我继续按当前授权推进。'
    return f'进度更新：{pos}\n刚确认：{done}\n下一步：{nxt}\nOwner：{owner}\n'

def main(argv=None)->int:
    ap=argparse.ArgumentParser(description=__doc__); sub=ap.add_subparsers(dest='command',required=True)
    for name in ('render','validate','check','progress'):
        sp=sub.add_parser(name); sp.add_argument('--input',required=True,help='JSON file, or - for stdin')
        if name=='check': sp.add_argument('--response',required=True,help='UTF-8 draft of actual final reply')
    a=ap.parse_args(argv)
    try:
        raw=sys.stdin.buffer.read() if a.input=='-' else Path(a.input).read_bytes(); d=json.loads(raw.decode('utf-8-sig'))
        if a.command=='progress': sys.stdout.write(progress(d)); return 0
        result=render(d)
        if a.command=='render': sys.stdout.write(result)
        elif a.command=='validate': print('OWNER REPORT INPUT PASS：结构与中文叙述检查通过；不代表事实/测试已验证。')
        else:
            reply=Path(a.response).read_text(encoding='utf-8-sig').replace('\r\n','\n')
            if reply.strip()!=result.strip(): raise ReportError('拟发送正文与生成全文不同；缺提示词、行动或中文说明均不能只靠文件替代')
            print('OWNER REPORT DRAFT PASS：正文完整匹配；仍需实际发送到聊天。')
        return 0
    except (OSError,ValueError,TypeError,KeyError) as e:
        print('OWNER REPORT STOP: '+str(e),file=sys.stderr); return 2
if __name__=='__main__':
    for stream in (sys.stdout,sys.stderr):
        if hasattr(stream,'reconfigure'): stream.reconfigure(encoding='utf-8',errors='strict')
    raise SystemExit(main())
