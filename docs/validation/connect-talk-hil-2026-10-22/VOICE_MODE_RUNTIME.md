# I02b-1 语音模式路由首批验收

源码：da3814d，基线PR153合入后的ca7981f。无Runtime依赖。

## 已验证

- 13项路由/原生手势回归通过；完整401项测试通过。
- Spec与Standards分别发现的同一计时器P2已修复，两轴复核通过：原生手势单一按键所有权，取消/松开后旧阈值令牌无效，不会因重叠别名遗留录音任务。
- 当前模式无路由不跨模式借用，按下捕获路由直到松开，自定义F18/F19保持直发，显式Fn保留既有行为。

## 候选与限制

源码da3814d的0.2.3 arm64候选已构建，Developer ID签名及deep/strict校验通过，安装到/Applications并核对AhaKeyGitCommit。启动后语音桥运行、权限4/4、原生事件监听启动，硬件上报Codex模式。原生控制读取Key4编辑页得到Backspace，读回和说明位于主键下方，返回及窗口截图成功；未修改或保存配置。后台读回connected=true、physicalSwitchState=0、switchState=0、approvalAutoVerified=true、presentationBusy=false。自动测试不启用麦克风，不能替代真实语音回填、系统tap失活和四模式混用的实体联合验收。

不改写键盘、不关闭Consumer、不重绑Voice；Key1原位保存、逐模式原生/AhaType处理方案与录音策略锁定仍属I02b-2，Consumer逐模式混用仍有固件依赖。
