param([string]$Source=(Join-Path $PSScriptRoot 'ManagedBridge.cs'))
$ErrorActionPreference='Stop'
$text=[IO.File]::ReadAllText($Source)
$start=$text.IndexOf('internal sealed class SelectionSnapshot<T>')
if($start -lt 0){throw 'Missing actual selection class'}
$brace=$text.IndexOf('{',$start);$depth=0;$end=-1
for($i=$brace;$i -lt $text.Length;$i++){
    if($text[$i] -eq '{'){$depth++}
    if($text[$i] -eq '}'){$depth--;if($depth -eq 0){$end=$i;break}}
}
if($end -lt 0){throw 'Unbalanced actual class'}
$actual=$text.Substring($start,$end-$start+1)
Add-Type -TypeDefinition (@'
using System;
using System.Collections.Generic;
'@ + $actual + @'
public static class SelectionProbe {
    public static void Run() {
        var selection=new SelectionSnapshot<string>();
        var sameNames=new Dictionary<string,string>{{"id-A","AhaKey"},{"id-B","AhaKey"}};
        string foreground=selection.Publish(sameNames,false,false);
        selection.Publish(new Dictionary<string,string>{{"id-C","AhaKey"}},true,false);
        if(!selection.Contains(foreground,"id-A")||!selection.Contains(foreground,"id-B")||selection.Contains(foreground,"id-C"))throw new Exception("late background overwrote user choice");
        selection.Publish(new Dictionary<string,string>(),true,false);
        if(!selection.Contains(foreground,"id-B"))throw new Exception("empty observation invalidated selection");
        selection.Publish(new Dictionary<string,string>(),false,true);
        if(!selection.Contains(foreground,"id-A"))throw new Exception("active session changed selection");
        string fresh=selection.Publish(new Dictionary<string,string>{{"id-C","AhaKey"}},false,false);
        if(selection.Contains(foreground,"id-A")||selection.Contains(fresh,"id-A")||!selection.Contains(fresh,"id-C"))throw new Exception("fresh foreground did not replace old candidates");
    }
}
'@)
[SelectionProbe]::Run()
Write-Output ('PASS actual C# selection class: foreground/background reverse completion, duplicate names, empty observation, active session, stale choice. SHA256='+(Get-FileHash -LiteralPath $Source).Hash)
