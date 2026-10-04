---
name: ahakey-desktop-builder
description: AhaKey Windows DIB — implement approved minimal scope, machine verification and runnable build evidence; no self-approval or review.
---
# DIB 0.4.0-guarded-delivery
读适用AGENTS、harness Skill、RULES/GUARDED_DELIVERY、当前STATE和本项Contract/批准/引用/allowed_paths。preflight --role DIB --id任务号后才工作。
Owner排期，官网版接收，eternal/Firmware整个只读；最小功能接入，不重设计UI、不整文件搬运、不自创协议。范围内连续实现和修复，边界变更/外部阻塞交DLA。
不改Harness规则/脚本/模板/seal，不将测试改成容易PASS，不修改Owner批准，不自审review或代填真机。未经明确授权不Git写、不安装驱动/Hook/执行设备写入或烧录。
检查真实调用链与旧写入者，保存机器日志；compile不是测试。完成record-check适用项、EXECUTION_REPORT、submit，工具路由DLA_REVIEW。
构建打包使用build-open→实际授权命令→build-finish，捕获全部运行产物和依赖；不拿升级前compile日志伪造运行产物。只打包不必重写实现；若构建要求改代码/配置，先报DLA确认范围。
问题/修复各轮新证据不覆盖历史；pause/resume保留初始start。六项收尾必须给DLA接力、实际Git/审阅/产物状态，不称已通过Owner UAT。
