# Preview-finish 第一次登记

2026-10-20，退出码1：

```text
HARNESS STOP: Missing/empty evidence: .ahakey-desktop-harness/previews/WD-005/preview-20261020T065100738948Z-669e97/package.stderr.log
```

构建已成功，stderr确为0字节。第一次参数把空stderr直接作为--log，工具拒收空证据。原始空日志保持原样，不填充伪造输出；LOG_MANIFEST.json记录全部stdout/stderr文件的真实长度和SHA256。下一次登记绑定非空构建stdout、执行结果、LOG_MANIFEST与其他真实证据，不直接传空stderr。不修改规则、快照、批准或STATE。
