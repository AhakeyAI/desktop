# Build Report — WD-003

- token: `20261008T005913928548Z-cecb3e`
- candidate: `23a898d97481cdc4b08ec4a50159d22f27c3619b`
- command: `git archive 23a898d97481cdc4b08ec4a50159d22f27c3619b; JAVA_HOME=D:\jdk-17.0.19.10-hotspot; mvn -B -DskipTests package; copy target\ahakey-studio-1.0.0.jar and target\lib into the token runtime directory`
- entrypoint: `Set-Location -LiteralPath 'C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\builds\WD-003\20261008T005913928548Z-cecb3e\runtime'; & 'D:\jdk-17.0.19.10-hotspot\bin\java.exe' -cp 'ahakey-studio-1.0.0.jar;lib\*' com.example.ahakey.Main`
- runtime_kind: `jar_classpath`

Build evidence is append-only and MUST NOT be appended to EXECUTION_REPORT.md.
