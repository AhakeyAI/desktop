# WD-010 R2 未冻结代码提前审阅

观察时间：2026-11-05 12:37–12:39（Asia/Shanghai）。审阅聊天：`01a1a970-ac70-77a3-bfc4-3e4ebe225604`。

这是原 DLA 委托的只读提前检查，不是正式复审，不登记 PASS/FAIL，不修改生产或 Harness 状态。DIB 正在修改，以下只针对本次读到的实现；新冻结包应重新核实。第1轮 `FINAL_REVIEW.json` 保持原字节，SHA256 仍为 `3dfcdbab7881cb5cf8ad6c6af56282d0bc14b72b3737c8d85cea6909a06fcafa`。

## 已看到的修复方向

- `LOCAL_PREPARING` 与 `SENDING` 分开，持久化准备保留原草稿文件；发送边界之后才清理 live draft。准备 journal 备份运行偏好并支持回滚；legacy PREPARED 不被当成安全未发送。
- 原 DLA 已指出的 clear 后 journal 清除失败、离线/人工关联拦住本地清理问题已有对应 `localCleanup` 状态及 UI 分流。本记录不重复把这两项报作新增缺陷，正式冻结时仍需核对测试。
- FR-03 新增 `OperationResult.delivery`，能把该请求自身触发401所产生的空token新session传给UI；UI在这条路径展示终态并切回登录页。主动换号仍通过代次检查抑制旧结果。
- FR-02 增加“兑换新码”，成功后显式清空并重新确认；未知结果仍不自动重发。

## ER2-01 / P1：启动回滚失败后，稍后本地清理成功没有恢复已载入默认值的内存模型

涉及：`StudioStore.java:48-53`、`StudioController.java:133,198-203`、`FactoryResetService.java:46-47,133-137`，以及 `AiRuntimeDisplayService.java:112`。

明确路径：

1. 上次进程退出时存在 `LOCAL_PREPARING`，原 `studio-draft.json` 仍完整，运行偏好可能已准备为 SINGLE。
2. 本次启动 `StudioStore.loadOrDefault()` 首先调用 `recoverPreparation()`。若运行偏好原子恢复或 journal 删除暂时失败，catch 直接返回默认草稿。
3. `StudioController` 把这个默认草稿载入 live `StudioState`；运行偏好服务也会载入当时磁盘上的值。随后 `FactoryResetService` 构造时若恢复仍失败，进入可重试本地清理。
4. 存储恢复可用后点击“重试本地清理”，`queryAgain()` 成功恢复磁盘、清掉 pending，然后仅 unlock/publish，没有将原草稿重新载入 `StudioState`，也没有恢复 runtime 的 live mode。
5. 用户看到的仍是默认配置。此后修改草稿或仅选择模式，`revision/selectedMode` listener 会走 `persistDraft()`；由于 pending 已清掉，`StudioStore.save()` 把这个默认模型覆盖到原草稿文件。原始草稿最终丢失，虽然提示声称“草稿保留”。若启动第一次恢复失败、service 构造时第二次已成功，同样没有重新载入早先丢弃的草稿。

这不是原 DLA 所述“清理按钮不可达”的重复问题，而是可达并成功之后的模型恢复缺口。仅保留文件字节不足以满足 FR-01 的保留语义。

建议：区分启动时尚未成功载入原模型与本进程 live 草稿始终保留的情况。在任何普通持久化重新启用前，完成原草稿/运行偏好的载入及状态同步；避免对本进程已有 live 编辑无条件重载磁盘。必要时保持初始化待恢复状态而不是先给可保存的默认模型。

补证据：用实际启动加载顺序，持久化一个可辨识的非默认按键/描述和 MULTI，模拟准备中进程退出；首次回滚失败，稍后点击实际本地清理后，验证 UI/live model恢复原值、零恢复start，然后选择模式/修改另一字段并重启，原字段仍保留。还应覆盖第一次 `loadOrDefault` 失败、构造 service 时恢复成功的变体。

当前 `RestorePreparationChecks` 重启用例只验证立即回滚成功后的磁盘字节；其他失败用例在失败前已经建立正确 live 草稿，因此不覆盖这里的初始化缺口。

## ER2-02 / P2：并发同账号请求先触发401，成功交易仍失去 delivery session

涉及：`AhaTypeService.java:163-166`、`CloudAccountManager.java:59-69,144-150,161-163`、`CloudAccountDialog.java` 的付款/兑换终态回调。

新 delivery session 仅通过**本次请求的** `CloudFailure.fallbackSession` 传递。`AhaTypeService.request()` 只有 `current(s)` 仍为真时才设置 fallbackSession；同账号另一请求已经使其失效时，当前请求抛出的401携带 null。

可控顺序：

1. 付款轮询已经读取到 `paid` 并通过 `currentPoll`，随后其 `/users/me` 刷新在途。
2. 用户在仍可交互的账号主窗口点击刷新，或另一云端请求并发收到401。该请求先调用 logout，generation递增，属于服务端会话失效，没有主动退出或换号。
3. 付款的资料刷新再收到401；旧 session 已不current，故其 exception.fallbackSession为null。`refreshForOperation` 返回旧s，`complete` 拒绝投递，付款窗口一直显示“正在查询付款结果”，worker已结束。若另一401发生在进入refresh之前，`refreshForOperation` 的首行也直接返回旧s，结果相同。
4. 成功兑换的刷新与并发401同样受影响。

建议：保存足够的会话失效来源/代次关联，让同一原账号session因服务端失效而已确认的操作终态可以投递到自己的窗口；后续主动退出、重新认证、换账号必须切断这条关联。不能简单改用任意当前session或移除current检查。

补证据：fixture用两条受控请求，在paid或redeem成功后阻塞该笔资料刷新，让另一请求先401，再释放该笔401；验证实际窗口显示“成功但资料未刷新/请重新登录”，停止进行中。再在两个401之间主动退出/登录另一账号，验证旧结果不进入新账号UI。

## 本轮证据身份与边界

静态调用链结论，未运行fixture、未构建、未调用真实云端或设备。以下是本次观察的工作区字节身份，不是新审阅包指纹；DIB后续变更可能使其过期。

| 文件（均在 src/main/java/com/example/ahakey 下） | SHA256 |
|---|---|
| service/FactoryResetService.java | `33edf0f97512661785b344e4ace2743474a0128436805a745bcb1952610ce5b1` |
| service/FactoryResetStore.java | `820604bda21d27ec94887c17ff212cdbef0686f769607eb34bf7ccc0d312a73a` |
| util/StudioStore.java | `e9c8392655b95eea364abd14b24ba7c7503da647c512f22310e72c4f35af827b` |
| service/CloudAccountManager.java | `63c155fa843c6da5c65b077cc13a3817d5265a326ebb80a6e736f973030def89` |
| service/AhaTypeService.java | `74e2acdad9004bae8eb5b87996d519835b115a3557cc14273393ca2160aa68bf` |
| view/CloudAccountDialog.java | `efba5ca802dea8d3858487efd1a41ff9d79766a0cc969f9bac485b3814eaa21e` |

原 DLA 可直接读取本文并在当前 FIX 中交 DIB 处理；不要求 Owner 再次转发或批准。最终仍等待新冻结 pack，在 `FINAL_REVIEW_R2.json` 使用顶层中文 analysis 字符串、详情放 analysis_details。
