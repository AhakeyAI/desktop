import { Check, Cloud, Cpu, MessageCircle, Monitor } from "lucide-react";
import { Provider } from "./contracts";

export function ProviderPicker({value,onChange,windows}: {value:Provider;onChange:(provider:Provider)=>void;windows:boolean}) {
  const choices = [
    {id:"wechat" as const,label:"微信输入法",detail:"输入法语音",icon:MessageCircle,windows:true},
    {id:"windows-native" as const,label:"Windows 听写",detail:"Win + H",icon:Monitor,windows:true},
    {id:"local" as const,label:"本地模型",detail:"SenseVoice · 离线",icon:Cpu,windows:false},
    {id:"doubao" as const,label:"豆包云端",detail:"API · 流式识别",icon:Cloud,windows:false},
  ].filter(choice=>windows||!choice.windows);
  return <div className="provider-switcher" role="group" aria-label="语音识别渠道">
    {choices.map(({id,label,detail,icon:Icon})=><button key={id} className={`provider-option ${id===value?"selected":""}`} aria-pressed={id===value} onClick={()=>onChange(id)}>
      <span className="provider-option-top"><Icon size={20} aria-hidden="true"/>{id===value&&<Check size={15} aria-hidden="true"/>}</span>
      <strong>{label}</strong><span>{detail}</span>
    </button>)}
  </div>;
}
