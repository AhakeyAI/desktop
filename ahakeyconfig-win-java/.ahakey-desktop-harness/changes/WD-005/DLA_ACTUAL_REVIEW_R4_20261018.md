# WD-005 revision 3 / round 4 实际差异审阅

结论：FAIL，原合同内退修。未发现已确认 P0/P1；三项 P2 运行态正确性问题阻止本轮 Preview 放行。不是由于缺测试直接认定故障，而是以下真实调用链形成确定的错误路径。本轮只读代码/证据，未执行测试、构建、应用、设备或 Git 写入。

## 固定输入与证据

- 原起点：41c034171e60b2d4962b0adbe8f3cffbf80a0436；HEAD：f595262207796dbf325cb9951ed3dc02b4887362（源码存档，非 candidate）。
- 代码指纹：e298ea1dd15131f508a602deed06181e0a53c6ff8b5c2366674dfc0cfb44d49d。
- 固定包：reviews/20261018T100038260474Z-fa1f1f/PACK.json。
- canonical pack SHA：9d49dbe76b1f7e0df5e387a4bc4e0db388e3ffe6963917b7de38538101167f52。
- ACTUAL_DIFF SHA：77c0ce243ce472e1c1ce0846e42dd8d4854e5ed6ebec5bdaeda591ce4e613a98。
- 审阅累计30文件，逐文件分析见同名JSON。根REVIEW.json仍为历史第三轮记录，不覆盖，也不引用为本轮PASS。
- verification绑定的第四轮报告/检查表/接续与最终日志为本轮执行依据；冻结根EXECUTION_REPORT及report_sha不是第四轮执行报告。25份检查表证据哈希均匹配，最终日志分别为175、36、72、72、42项，共397项；本DLA未重跑。
- 只读辅助审阅：Laplace检查Spec/runtime，Halley检查Standards/resources/UI；原DLA复核三项发现。这些辅助不是正式high-impact fresh。

## R4-F1 / P2：忽略显示更新时同时丢失会话终态

位置：AiRuntimeDisplayService.java:308-318；后续prepareApply:397、sendAppliedSnapshot:526。

确定路径：SINGLE收到A开始，随后B开始；A完成因为不属于singleOwner而返回IGNORED。该分支没有更新A的liveFacts，旧RUNNING仍有效。五分钟内切MULTI并应用A的可用绑定，prepareApply和最终snapshot均从liveFacts取回RUNNING，把已结束会话重新点亮。

要求：分离“可信会话事实入库”与“是否允许覆盖当前SINGLE显示”。可信且可精确归属的A完成应更新A事实，但不能覆盖当前B的显示/待补发状态。保留后台过滤、身份冲突拒绝、TTL和连接代次，不引入新的多会话聚合产品语义。

回归：A开始→B开始→A完成；验证B显示保持，之后MULTI应用A不得得到RUNNING。覆盖上传租约期间相同顺序，证明补发是当前显示所有者的最新状态，而切模式后的事实仍正确。

## R4-F2 / P2：匿名兼容事件清空交错保护

位置：AiRuntimeDisplayService.java:303、308、312；HookDispatchServer的Kimi通用事件入口。

确定路径：Codex A开始→无session_id的KimiUserPromptSubmit→A迟到SESSION_END。Kimi的identity为空字符串，非终态把singleOwner置空。A终态因此绕过!singleOwner.isBlank判断，发送结束状态，覆盖当前Kimi；租约期间则覆盖Kimi待补发状态。

要求：保留匿名旧Hook正常SINGLE兼容，但不能把“没有会话ID”表示成“没有当前显示所有者”从而解除其他已知会话迟到终态保护。可在进程内保留工具来源/匿名显示占用信息；禁止伪造会话ID、cwd兜底、屏蔽所有匿名事件或改权限allow策略。匿名同工具无法判定的情况应保留明确局限，不声称完全解决。

回归：上述混合工具顺序的立即发送和上传期间pending两种路径；同时验证匿名工具自身正常开始/完成不被统一屏蔽。

## R4-F3 / P2：补发失败给旧事实续期

位置：BleManager.java:772、779-786。

确定路径：t=0收到事件并因租约保留pending；t=4分钟释放租约补发，flush调用sendRuntimeState先把deferredRuntimeAt改为当前时间，之后sendCommand抛IOException，pending保留。连接代次未变时，t=6分钟下一次租约释放会把原事件当作两分钟的新事实发送。无需新Hook事件，已突破原五分钟生命周期。

要求：事实时间只在接收新事件时推进；重试/补发必须保留原observed时间。保留未知ACK隔离、连接代次清理及最新事件替换，不改TTL、不加定时保活/盲重试。

回归：使用受控传输抛IOException和受控时间，验证原事件第六分钟不再发送；新的可信事件可重新计时；重连仍不补发旧代次。

## 已核对但不扩大结论

- UI局部白字/禁用态、模式分区/全局亮度/草稿保护、OLED轻提示均已接真实入口；完整Inspector、高DPI和产品进程日志仍待新Preview。
- 上传保留单租约、固定传输/连接、逐包ACK、异常隔离及诊断；旧84/85入口在全量保存过滤。后台88回读与身份/输入/Mode串行化，FX提交保留操作/编辑/连接身份；未发现这些路径新增确定缺陷。
- 固件只读command_solve核对88/89/8A/8B/8C/8E格式；display_presentation_select当前仍有非主槽回退。RT-03明确留给固件，不以Windows伪造valid掩盖。
- UP-01/UP-02真实原因、缺来源后台事件、BLE性能A/B、桥接新源码复审/驱动身份、完整USB/BLE及Owner验收保持待办。桥接foreign接受不等于功能PASS。

## 定点修复边界与路由

按正式record-check fail及request-fix路由，不修改生产源码。DIB主要修改AiRuntimeDisplayService.java、BleManager.java和displayconfig测试目录；仍受当前R3 allowed_paths及文件内职责约束。其他产品/桥接/固件/协议扩展需先交DLA，不借退修改动无关模块。

修复后新增报告和证据，重跑受影响断言及适用回归，按当时有效round登记再submit。保留本轮固定pack/报告/起点/批准及历史dirty；不复用旧轮PASS或旧Preview token冒充新实现。通过新actual review后才决定Preview，formal fresh/candidate/交付身份另行完成。
