param(
    [string]$JavaHome='D:\jdk-17.0.19.10-hotspot',
    [string]$Maven='C:\Program Files\apache-maven-3.9.12\bin\mvn.cmd',
    [string]$OutputRoot=('target/wd007-checks-'+(Get-Date -Format 'yyyyMMdd-HHmmss')),
    [string]$BridgeExecutable,
    [string]$KimiConsumer=(Join-Path $env:APPDATA 'uv/tools/kimi-cli/Lib/site-packages/kimi_cli/soul/approval.py')
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Use a new output directory; evidence is never overwritten.'}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$env:JAVA_HOME=$JavaHome
& $Maven -o '-Dmaven.repo.local=.m2repo' -DskipTests test-compile *> (Join-Path $OutputRoot 'compile.log')
if($LASTEXITCODE -ne 0){throw 'Compilation failed; see compile.log'}
& python (Join-Path $PSScriptRoot 'wd007/run-checks.py') --java (Join-Path $JavaHome 'bin/java.exe') --output (Join-Path $OutputRoot 'behavior')
$behaviorExit=$LASTEXITCODE
& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'wd007/test-managed-selection.ps1') *> (Join-Path $OutputRoot 'managed-selection.log')
if($LASTEXITCODE -ne 0){throw 'Managed selection checks failed'}
if($BridgeExecutable){
    & python (Join-Path $PSScriptRoot 'wd007/test-managed-ipc.py') --bridge $BridgeExecutable *> (Join-Path $OutputRoot 'managed-ipc.log')
    if($LASTEXITCODE -ne 0){throw 'Managed IPC process checks failed'}
}
if(Test-Path -LiteralPath $KimiConsumer){
    & python (Join-Path $PSScriptRoot 'wd007/test-kimi-consumer.py') --java (Join-Path $JavaHome 'bin/java.exe') --consumer $KimiConsumer *> (Join-Path $OutputRoot 'kimi-consumer.log')
    if($LASTEXITCODE -ne 0){throw 'Installed Kimi consumer replay failed'}
} else {throw 'Supply the read-only installed Kimi consumer with -KimiConsumer'}
if($behaviorExit -ne 0){throw 'One or more behavior suites failed; see behavior/RESULTS.json'}
Write-Output "PASS WD-007 machine checks: $OutputRoot (not hardware/UAT or package admission)"
