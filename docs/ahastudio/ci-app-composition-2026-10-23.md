# CI客户端产物完整性修复

日期：2026-10-23。范围：G54/P02、L02/Q04。CI产物用于下载验收，必须是完整客户端；正式签名公证与发布组合门槛保持原流程。

## 实际反例

已下载绿色CI run 39839656358（源码a2cbe4c）的AhaKey-Studio-macOS.zip，直接读取归档：有Contents/MacOS/AhaKeyConfig，缺少Contents/MacOS/ahakeyconfig-agent；Info.plist没有AhaKeyGitCommit、NSAppleEventsUsageDescription，最低系统写成12.0，而Swift Package平台是13.0。`/tmp/ahakey-ci-bundle-red.json`记录该结果。归档没有被安装或执行。

原因是CI调用的scripts/package_app.sh只组装主程序，另一份完整scripts/build.sh才组装Agent、语言资源、图标与完整权限/来源字段。AgentManager依赖同包内Agent，因此“编译绿”不能代替完整安装包。

## 目标与实现合同

- package_app.sh委托同一份完整build.sh，默认仅构建本机架构，保留APP_VERSION/APP_BUILD覆盖。正式构建直接使用build.sh的原通用架构和Developer ID路径，不改变公证/发布校验。
- CI入口明确ad-hoc签名，不使用机器私钥，不安装或打开客户端。不能因继承INSTALL_TO_APPLICATIONS或LAUNCH_AFTER_INSTALL而产生安装动作。
- build.sh默认build号仍来自git提交数；显式APP_BUILD覆盖与原CI入口一致。
- CI打包后检查主程序和Agent为包内正常可执行文件、源码SHA与GITHUB_SHA一致、身份/版本/最低系统/四项TCC用途字段、两种语言资源完整；不完整产物不得上传。
- 该检查只验证CI组成。正式产物的Developer ID、hardened runtime、公证、同DMG和发布证据仍由既有verify_release_installer及受保护发布流程验证。

## 验证

5项组成回归覆盖完整/缺Agent/不可执行或符号链接Agent/缺来源权限或错误最低系统/缺语言资源。另实际运行CI打包入口，检查完整包并执行深度严格签名校验；通过后再从提交版本构建Developer ID候选。源码Swift行为未改，不将此打包修复重复计为功能开发。
