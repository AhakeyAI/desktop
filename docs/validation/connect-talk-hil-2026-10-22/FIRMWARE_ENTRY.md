# 固件升级入口与HEX负例补验

## 控制服务故障及修复

旧候选342e4e8：从更多→固件升级，CUA读取时native pipe closed。最新SkyComputerUseService ips为EXC_BREAKPOINT/SIGTRAP，顶层_assertionFailure/Array.remove(at:)与此前Inspector默认GroupBox触发形态相同。用户既有授权范围内用AppleScript只对Studio发送Escape退出该页，原生主窗口恢复；没有请求用户重启Codex、修改控制服务二进制或系统权限。原ips仅本机private留存。

ca4bed6将该页三处分组改用既有StudioInspectorSection与显式Label，保留固件文件、USB ISP、烧录状态标题/图标及全部内容。未改变校验、数据清空确认、等待目标、擦除或刷写逻辑。474项完整测试、Spec和Standards窄审通过，签名0.2.3 arm64候选已安装，包内source与deep/strict验证通过。

## 实际UI验收

1. 同一更多→固件升级路径原生控件树读取成功，三组内容、关闭/选择HEX/恢复内置及确认复选框可访问，未再触发本次服务崩溃。
2. 内置AhaKey-X1-firmware-eternal-dev-5a84c2a-1.4.6.hex显示校验通过，SHA256 f7df11438263aadedb5ad2c05e6f7162c66afc3d36193fac87d7399a7f25976e；没有将它称为当前新固件的推荐或recovery-safe版本。
3. 数据清空确认未勾选，开始等待设备按钮禁用。此结论不是“没有ISP时按钮禁用”，等待设备本来由后续流程处理。
4. 通过原生文件对话框选择26字节、第一条checksum错误的Intel HEX，实际显示第1行校验和错误；selectedFirmware撤回为无可用文件、开始按钮仍禁用。验证在访问设备前发生，没有勾选清空确认/开始等待/擦除/刷写。
5. 恢复内置选择后重新显示校验通过与ready状态，确认仍未勾选；关闭该页返回正常客户端。

这是文件选择/校验/门控及原生UI兼容补验，不是USB ISP目标识别、错误芯片实测、实际烧录、失败恢复或刷后身份读取的替代。那些项目仍按G52/L03及WS5合同推进。
