package com.example.ahakey.firmware;

import java.util.Map;

public final class WchIspExitCodes {
    private static final Map<Integer, String> MESSAGES = Map.ofEntries(
        Map.entry(0, "成功"),
        Map.entry(1, "命令行参数无效"),
        Map.entry(2, "配置文件读取失败"),
        Map.entry(3, "ISP 初始化失败"),
        Map.entry(4, "串口参数无效"),
        Map.entry(5, "未找到处于下载模式的设备"),
        Map.entry(6, "芯片型号不匹配（需要 CH582）"),
        Map.entry(7, "读取设备信息失败"),
        Map.entry(8, "固件文件路径无效"),
        Map.entry(9, "固件长度无效"),
        Map.entry(10, "读取固件文件失败"),
        Map.entry(11, "HEX 转 BIN 失败"),
        Map.entry(12, "解除写保护失败"),
        Map.entry(13, "烧录失败"),
        Map.entry(14, "校验失败"),
        Map.entry(100, "WCHISP 未知错误")
    );

    private WchIspExitCodes() {}

    public static String describe(int exitCode) {
        return MESSAGES.getOrDefault(exitCode, "WCHISP 错误码 " + exitCode);
    }
}
