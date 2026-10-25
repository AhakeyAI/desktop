## 问题摘要

Mac 客户端接入 WS4/WS5 Restore 时发现：Restore 成功并持久化为 `COMPLETE` 后，下一次明确发起恢复会被固件拒绝。即使正常重启后也一样。这里是“无法再次执行恢复操作”，并非键盘无法正常开机。

## 已核对的最新基线

- 分支：`harness/x1-refactor-main`
- 2026-10-25 重新 fetch 后仍为 `0a055ba95f857a1d32f05b79bcabd3ecfe78d4eb`。
- 接口：`0x9E` v1，`0x30` 查询状态、`0x31` 明确启动/重试。
- 本问题以最新源码和内存模拟存储的 host 探针确认；**未在用户键盘上执行破坏性恢复，也未声称完成 HEX 或真实掉电验收**。

## 实际结果与原因

[`k1_restore_store_restore_begin`](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/0a055ba95f857a1d32f05b79bcabd3ecfe78d4eb/APP/services/k1_restore_store.c#L391) 仅允许 `NEVER` 或 `INCOMPLETE` 进入新尝试：

```c
if (state != K1_RESTORE_NEVER && state != K1_RESTORE_INCOMPLETE) return 0;
```

完成后保存 `COMPLETE`，再次明确启动会返回失败；外接供电、writer 空闲也不能改变此结果。重启会重新读回该持久化状态，仍然拒绝。失败重试则可以从 `INCOMPLETE` 完成。

原有 host suite 验证了失败→重启→明确重试，但未覆盖成功→重启→再次恢复。

## 可复现步骤（不需要键盘，host fake EEPROM）

1. 从上述 commit 提取原有 `tests/host/restore_initialization/test_restore_initialization.c`、fake `main.h`、`k1_restore_store.[ch]`、`restore_initialization.[ch]`。
2. 先运行原有 host suite，结果通过。
3. 清空 fake flash，设置外接供电=1、writers_idle=1、apply_defaults 成功，第一次调用 `restore_initialization_start`。
4. 使运行缓存失效，调用 `restore_initialization_boot` 模拟重新读取持久化状态。
5. 再次使用相同有效条件调用 `restore_initialization_start`。

本机 clang C99，`-Wall -Wextra -Werror` 下结果：

```text
PASS: RESTORE_INITIALIZATION_HOST_TESTS
first=1 second_after_boot=0 state=3 attempts=1 apply_calls=1
```

其中 state=3 为 COMPLETE。第二次尚未进入 apply_defaults，尝试序号也未增长。

## 期望与建议验收

- 用户明确选择再次恢复时，允许 COMPLETE → IN_PROGRESS，新恢复尝试 ID 增长；不自动重复恢复。
- 验证新尝试使旧路由事务/旧请求失效，保持共享存储原子性和正常后续路由修改；不要通过删除持久化记录、清蓝牙绑定或重新刷机来绕过状态机。
- 外接 USB 供电与 writer/upload 冲突门控继续有效。
- 增加成功→再次恢复、成功→重启→再次恢复、成功→改键位/路由→再次恢复、第二次中途失败→重启→明确重试，以及供电中断/存储失败的测试。
- 补充实际产品板/精确候选 HEX 验证与恢复范围读回；host fake 测试不替代这些验证。

## 请同步明确恢复范围

当前 [`restore_initialization_apply_defaults`](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/0a055ba95f857a1d32f05b79bcabd3ecfe78d4eb/APP/sub_main/main.c#L878) 重置键位、模式、待机及部分显示/灯光状态；不能据此承诺清除所有素材字节或蓝牙配对。

[`command_k1_restore_handle`](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/0a055ba95f857a1d32f05b79bcabd3ecfe78d4eb/APP/sub_main/command_solve.c#L434) 构造恢复后的 K1 路由为前三模式普通 F18、第四模式空普通绑定。请明确这是约定默认值还是需调整，以及 Voice onboarding、描述/宏、拨杆绑定、灯光、素材引用/原始字节、蓝牙绑定和身份各自的恢复/保留规则。**单模式恢复 Consumer 是独立能力，不能与整机 Restore 的默认路由混为一谈。**

## Mac 侧配合

客户端按已验证命令与状态接入，完成需结合状态和实际读回；未完成/失联只查询，不自动重发破坏命令。现有 Coffee 图片与用户配置不用于本次破坏性验证。可重复恢复与明确恢复范围未补齐前，不将完整恢复出厂标为已完成。

已提交：https://github.com/AhakeyAI/AhaKey-X1-hardware-source/issues/9
