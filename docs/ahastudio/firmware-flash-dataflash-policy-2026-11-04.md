# Mac 烧录 DataFlash 策略对齐

日期：2026-11-04。范围：客户端 G52/L03；本轮未对键盘执行擦除、写入或恢复。

## 问题与行为

旧客户端在每次烧录前固定执行 `eeprom erase`，不符合最新 HW1 交付说明的“保留DataFlash，不整片擦除”。现在默认选择“保留配置升级”：检测 CH582 后仅擦程序区并写入、校验、复位；“清空配置刷写”需用户明确选择和重新确认，才先擦 DataFlash。切换策略或重选文件会清除准备确认。每次开始时同时锁定文件与策略，重复点击不能替换正在进行的操作；任何失败均不自动转为清空配置。

保留策略只承诺客户端不主动擦除 DataFlash，不承诺任意固件之间的数据格式兼容。目标固件可能迁移、忽略或重新初始化不兼容记录，因此仍需查阅交付说明、备份并在升级后独立读回。清空会影响键位、路由、灯光等配置及蓝牙绑定；外部素材是否继续可用取决于固件元数据。不能将此发现直接归因为历史 Reconnect 的唯一原因。

## 一手证据

- [固件交付索引](https://github.com/AhakeyAI/AhaKey-X1-hardware-source/blob/72346b001710d573980a7d398b9e0dced8ff627c/FIRMWARE_INDEX.md)：HW1 指明保留 DataFlash。
- 本机内置 arm64 工具只读 `--version` 为 wchisp 0.3.0；本轮核对的是同版本上游源码，未声称对内置二进制做了可复现构建比对。
- [wchisp v0.3.0 CH582 定义](https://github.com/ch32-rs/wchisp/blob/f0f13c471bf04e050b987c19bc80bc394a3dca47/devices/0x16-CH58x.yaml)：CodeFlash 458752字节（448KiB），DataFlash 32768字节（32KiB），起点458752。
- [命令入口](https://github.com/ch32-rs/wchisp/blob/f0f13c471bf04e050b987c19bc80bc394a3dca47/src/main.rs)：`erase`按CodeFlash容量擦除；`eeprom erase`单独擦DataFlash；`flash --no-erase`不再重复擦除，仍默认校验与复位。
- [底层实现](https://github.com/ch32-rs/wchisp/blob/f0f13c471bf04e050b987c19bc80bc394a3dca47/src/flashing.rs)：`erase_code`与`erase_data`使用不同协议命令。固件 WS4-CP1 wire audit 及 BLE 初始化路径将绑定 SNV 也映射在 DataFlash，不能将全擦解释为只清键位。
- 客户端 Intel HEX 校验始终限制448KiB程序区；保留策略未放宽镜像范围、哈希、目标芯片或刷后身份检查。

## 验证边界

生产烧录器通过临时隔离的假工具实际启动进程，验证：默认升级从不发EEPROM擦除；显式清空按DataFlash→CodeFlash→写入执行；等待中的策略不可被另一请求替换；保留升级失败及重试不转为EEPROM擦除。原有目标拦截、取消、文件变更、180秒等待与重试回归保留。12项烧录生命周期专项及999项完整本地测试通过；中英文资源格式校验通过。

未进行本次真实ISP刷写，未声称配置、绑定或跨版本兼容的物理保持已通过。后续集中真机只需在重新获得本次刷写确认后验证保留升级及独立读回；清空分支不应为了界面验收而实际执行。
