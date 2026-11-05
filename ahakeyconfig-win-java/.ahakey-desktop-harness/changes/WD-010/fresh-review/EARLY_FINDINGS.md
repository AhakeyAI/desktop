# WD-010 独立预读：提前发现

日期：2026-11-05（Asia/Shanghai）。审阅聊天：01a1a970-ac70-77a3-bfc4-3e4ebe225604。

状态：EARLY_STATIC_FINDINGS_ONLY。当前仍为 IMPLEMENT / IMPLEMENT，STATE revision=267；没有正式冻结 pack。本记录不是最终 REVIEW、正式 FAIL/PASS 或测试执行记录。仅只读追踪当前代码，并写此文档；由原 DLA 判断并转 DIB，不修改生产或 Harness 状态，不向其他聊天发送消息。

## EF-01 [P1] 兑换任务未携带用户确认时的账号，会消费到执行时的新账号

位置：`src/main/java/com/example/ahakey/view/CloudAccountDialog.java:89-93`；`src/main/java/com/example/ahakey/service/CloudAccountManager.java:67-75`。

真实链路：兑换窗口创建时捕获 `session`，点击确认时检查 `aha.current(session)`，但提交后台只传 `account.redeem(value)`。`redeem` 自行再次调用 `aha.session()`，随后用该新 session 发送 POST。窗口回调中对旧 session 的检查只影响显示，不保护已发生的兑换。

触发顺序：账号 A 窗口点击确认兑换，后台任务在进入 `account.redeem` 之前被调度暂停；账号主窗口并未因兑换设置 `busy`，用户可退出 A 并登录 B；旧任务恢复执行时捕获 B 的 token，向 B 发兑换请求，旧 A 窗口的回调最后被丢弃。兑换码本应计入 A，却可能被消耗到 B，且用户看不到对应结果。

需要收口：在用户确认时冻结请求所属 Session/账号并传入服务，发送前验证仍有效，不允许服务用当前账号重新解释旧提交。结果写入也需保持相同代次；现有 `redeem` 在 `refreshProfile(s)` 返回后无再次校验便赋值 `redeemStatus`，退出期间迟到的刷新失败还会覆盖退出清空的操作状态。`createOrder` 同样由 UI 捕获 session、服务另取 session，也应对齐此请求绑定规则（账号页 busy 限制了普通 UI 换号路径，本项直接可达缺陷以兑换为主）。

建议验证：在真实 UI → 服务接缝的提交前设置可控制栅栏；A 点击后退出并登录 B，再放行；断言旧兑换发出 0 次，不出现携带 B token 的旧兑换码，也不更新 B 的提示。不要只测试 HTTP 已发出后的迟到响应。

## EF-02 [P1] 人工关联只传 boolean，确认可以迁移到弹窗之后接入的另一台 USB 设备

位置：`src/main/java/com/example/ahakey/view/FactoryResetDialog.java:47-57`；`src/main/java/com/example/ahakey/service/FactoryResetService.java:101-111`；`src/main/java/com/example/ahakey/service/FactoryResetStore.java:10-15`。

真实链路：人工确认弹窗显示 `currentTarget()` 的快照；同意后只调用 `queryAgain(true)`。服务在 worker 内重新取 `device.target()`，没有收到/验证弹窗中被确认的 Target、连接 generation 或 taskId。`definitelyDifferent` 只判断两个非空 BLE 地址冲突，不能挡住 USB A → USB B 的情况。

触发顺序：待确认记录属于 USB A；弹窗显示当前 A；弹窗打开期间或确认后 worker 开始前，物理连接换成 USB B。旧 boolean 授权随后把 B 设为 `bound`，并向 B 查询。如果 B 的 durable attempt 恰与待确认任务相同（attempt 是计数器，不是全球唯一任务身份），返回 COMPLETE 会进入旧任务的读回/清理流程，把 B 的结果当成 A 的结果。即使其他读回问题暂时阻止完成，错误绑定及对 B 的旧任务查询已经发生。

需要收口：人工确认凭证绑定弹窗展示的任务及准确 Target/transport/generation；在 worker 执行和请求前校验，任何连接变化作废，不能将 boolean 带到新目标。人工关联仍只允许查询，不扩大成硬件身份证明。

建议验证：使用两个 USB 目标、相同 attempt；在确认弹窗与服务执行之间切换 generation/path，断言 B 零查询、零读回，A 记录继续未确认；同一目标未变化时才允许人工查询。

## EF-03 [P1] 旧运行显示任务没有发送处的恢复代次校验，可在恢复解锁后补发

位置：`src/main/java/com/example/ahakey/service/AiRuntimeDisplayService.java:48-52,473-500,510-530`；`src/main/java/com/example/ahakey/service/BleManager.java` 的 `setRuntimeDisplayMode(mode,generation)`（本轮读取约1138行，后续编辑会移动）。

真实链路：`factoryResetStarted/maintenanceChanged` 清理 snapshot 和本地 displayMode，却没有作废已创建的 `ai-runtime-mode-send` 线程。`setDisplayMode` 的线程携带的只有 connection generation；`BleManager.setRuntimeDisplayMode` 在 commandTransactionLock 内仅校验连接 generation，再按当前 maintenance 状态发送。恢复前后如果没有断连，generation 不变。其 FX 完成回调同样只核对连接和显示能力，没有核对维护 epoch/恢复代次。

触发顺序：用户恢复前选择 MULTI，发送线程尚未真正进入发送；开始并完成一次同连接恢复，读回成功解锁；旧线程再执行，当前 maintenance 已允许普通写入，于是发出旧 `0x98 MULTI` 并把本地模式重新持久化为 MULTI，覆盖恢复后的 SINGLE。另一条 `onDeviceReady` 虽在调用前检查 maintenanceEpoch，但检查与真正取得发送锁之间存在空隙，不能保证排队任务在发送时仍属于原代次。

需要收口：恢复使所有显示模式/应用任务的 token 失效；在取得发送事务锁后、实际发送前检查冻结的 epoch/token，FX 完成回调也检查相同 token。不能只在 worker 创建或调用前检查，也不能仅靠工厂锁在执行期间拒绝请求，因为旧线程可能在解锁后才运行。现有 MULTI snapshot 的 `BooleanSupplier current` 在发送锁内检查可作为需要核对的同类接缝。

建议验证：暂停实际 setDisplayMode/onDeviceReady 任务到发送前，完成模拟恢复并解锁后再放行，捕获实际传输帧，确认旧0x98/0x99零发送、旧回调不写持久化偏好。单测只检验 snapshotPending=false 不覆盖此问题。

## EF-04 [P2] 重启/重连后恢复锁抢先建立时，生产读回缺少 catalog 重新准入，无法解除只读

位置：`src/main/java/com/example/ahakey/service/FactoryResetService.java:114-124,181-193`；`src/main/java/com/example/ahakey/service/BleManager.java:274-282,346-359`；`src/main/java/com/example/ahakey/app/StudioController.java:116-120,908-929`。

真实链路：重连 `resetDisplaySession` 清空 firmwareIdentity；待确认任务可由 `connectionChanged` 自动关联 BLE，或先将 USB 放入 quarantine。工厂锁建立后 Controller 的 `deviceFx`/`requestFirmwareCatalogKeyAfterConnect` 受 `normalAllowed()` 拦截，不再走普通固件身份读取。`FactoryResetService.production.Device.readback` 读取键位/K1/图片等后直接调用 `readDisplayConfig`，却没有在专用只读权限内执行 `readFirmwareCatalogKey(generation)`。`exchangeDisplay` 仍要求 `isDisplayAdmitted` 或 lights capability；identity UNKNOWN/DISCONNECTED 时必然拒绝。

触发顺序：应用带 SENT 记录启动或重连原设备，恢复 worker 在普通 catalog 读取前建立锁；人工/自动查询得到匹配 COMPLETE；生产读回到亮度/metadata时因未准入失败。再次点“重新读取”重复相同路径；普通身份读取持续被锁阻止。于是原设备实际已完成，Windows 却长期 READ_FAILED/只读。该路径不取决于恢复协议失败，而取决于启动时两个 worker 的顺序。

需要收口：在关联成功后通过工厂专用只读权限建立当前连接的真实固件身份/必要读能力，并核验 generation，之后执行读回；不能借此全局绕过 catalog 保护或假造 supported。若实际固件确实不提供必要能力，应明确保留真实缺口。

建议验证：使用真实 `production` adapter 和 BleManager/capability gate，初始 identity UNKNOWN、待确认记录存在；恢复查询为 COMPLETE，catalog/配置回复由隔离传输返回。断言专用只读链可获取身份并完成所有读回，且普通写入保持禁止。现有 `RestoreChecks.Device.readback` 仅计数/抛异常，不能证明这条生产链可走通。

## 并发编辑观察及未定案项

- 预读期间 DIB 正在修改。较早看到的“USB 未人工关联前普通写入放行”路径，随后已出现 `quarantined`、`protectCurrentTarget` 和 `BleManager.admitFactoryBoundary` 补充；因此不把较早版本的问题另列为当前未修复发现，也不将新守卫视为已验证修复。正式包需重核其完整链路及与 EF-04 的组合。
- VoiceInputManager 的 worker 前/后及注入承诺点存在录音代次检查，ProcessResult 也检查账号代次；本轮未据此宣布单次输出通过。`deliverFinal` 的 UI result callback 与 TopBar 的排队 FX 更新仍需在正式阶段检验新录音/停用边界，本轮没有把未复现的注入疑点当成发现。
- 本轮没有运行测试、构建、真实云端请求、设备命令或 Firmware 脚本。上述发现来自真实生产代码的可构造时序追踪；建议用例尚未执行。

## 本轮末次采样文件身份（不是冻结 pack）

工作区：`C:/Users/20825/Desktop/windows软件代码/desktop/ahakeyconfig-win-java`。采样后 DIB 仍可继续编辑；行号/哈希仅用于定位本轮观察，正式审阅必须重新绑定最终 pack。

| 文件（相对 src/main/java/com/example/ahakey） | SHA256 |
| --- | --- |
| service/FactoryResetService.java | 1e14167a1d299d131a3c5d53860df5f1a05adec47ef7e5942011ffad391c178f |
| service/BleManager.java | 0c747a819170a9fc97894fc85df7b734e58f083700ea156048cee301c180c7d7 |
| service/AiRuntimeDisplayService.java | 9446adf705d601367a6035f84a5d1fcff3f8ac7b879ae33ff7d94493520b92f6 |
| service/CloudAccountManager.java | 276ab0f106d4a412cca6d9131a6bd4939e655739a7b439616f642bbbf5295568 |
| view/CloudAccountDialog.java | 523d61068b22b7032ac5914c50808b86d6cd2fbbae22ed22c4095141bc7729ab |
| view/FactoryResetDialog.java | d3b6512addedc81251dbc7f6024e7198b367e0ef3469c15ca5ca52a77739a638 |
| service/VoiceInputManager.java | b9d1f5ee4f6c66300afd80beb26ad924d0cc1d1c81a72c4f88994db41745992a |

下一步：原 DLA 读取本记录并转 DIB 核查/修复；本独立身份等待固定 review_pack.json 和代码指纹，届时重新复核所有最终改动。没有正式结论，不用本文件替代 REVIEW.json。
