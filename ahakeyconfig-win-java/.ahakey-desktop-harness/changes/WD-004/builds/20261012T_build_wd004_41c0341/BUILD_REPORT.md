# WD-004 BUILD_ONLY Report

- Result: PASS
- Candidate commit: 41c034171e60b2d4962b0adbe8f3cffbf80a0436
- Candidate tree: 8618ec2f2b70743dba74c595f89af7f6d49aa647
- Command: mvn "-Dmaven.repo.local=.m2repo" --batch-mode --no-transfer-progress package -DskipTests
- Exit code: 0
- Java: D:\jdk-17.0.19.10-hotspot\bin\java.exe
- Artifact root: C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\changes\WD-004\builds\20261012T_build_wd004_41c0341\runtime-jar-classpath
- Jar: C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\changes\WD-004\builds\20261012T_build_wd004_41c0341\runtime-jar-classpath\ahakey-studio-1.0.0.jar
- Entrypoint: D:\jdk-17.0.19.10-hotspot\bin\java.exe -jar C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\changes\WD-004\builds\20261012T_build_wd004_41c0341\runtime-jar-classpath\ahakey-studio-1.0.0.jar
- Success log: C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\changes\WD-004\builds\20261012T_build_wd004_41c0341\maven-package-after-clean-fail.log
- Success log SHA256: 11cef6c315d57a565de151ece73641792fd4d9953424266ecfa5269551e8fd4d
- Prior clean-package attempt: FAILED due locked target/classes/ahakey.jpg; package rerun recompiled 60 source files and succeeded.
- Prior failed clean log: C:\Users\20825\Desktop\windows软件代码\desktop\ahakeyconfig-win-java\.ahakey-desktop-harness\changes\WD-004\builds\20261012T_build_wd004_41c0341\maven-clean-package.log
- Prior failed clean log SHA256: 7f3b519de38e3c6d217d3e360e2bdb1350acff86d58ba8c2f02a083d7190daa8

Limits: this records a Maven package/JAR-classpath build only. It does not prove app launch, EXE/installer packaging, Hook installation, device writes, Firmware validation, yellow PermissionRequest behavior, or Owner UAT.
