# WD-001 Machine Evidence — Compile

Role: DIB

Command:

`$env:JAVA_HOME='D:\jdk-17.0.19.10-hotspot'; $env:Path="$env:JAVA_HOME\bin;$env:Path"; mvn -q -DskipTests compile`

Result: PASS

Observed output: command completed with exit code 0 and no compiler errors.

Scope note: This is a Windows Java compile check only. No product app was launched, no device operation was performed, and no firmware workspace command was run.
