# Owner feedback — WD-001 T01 launch failure

Date: 2026-09-29
Source: Owner chat message in this Codex thread.

Owner executed:

```powershell
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' -version
& 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' -jar 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\target\ahakey-studio-1.0.0.jar'
```

Observed output:

```text
openjdk version "17.0.19" 2026-04-21 LTS
OpenJDK Runtime Environment Microsoft-13877129 (build 17.0.19+10-LTS)
OpenJDK 64-Bit Server VM Microsoft-13877129 (build 17.0.19+10-LTS, mixed mode, sharing)
错误: 缺少 JavaFX 运行时组件, 需要使用该组件来运行此应用程序
```

DLA interpretation: T01 failed with the published `java -jar` command before app launch. Device steps were not reached. This is not Owner UAT pass and not an installer failure.
