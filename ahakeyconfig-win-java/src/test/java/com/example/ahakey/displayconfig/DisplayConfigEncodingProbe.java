package com.example.ahakey.displayconfig;

import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.logging.*;

/** Process-only launch recipe probe. No application entrypoint or user configuration. */
public final class DisplayConfigEncodingProbe {
    public static void main(String[] args) throws Exception {
        String sample = "中文编码样本：上传并应用，草稿已保留。";
        System.out.println("STDOUT " + sample);
        System.err.println("STDERR " + sample);
        Logger logger = Logger.getLogger("wd005.encoding"); logger.setUseParentHandlers(false);
        ConsoleHandler console = new ConsoleHandler(); console.setEncoding("UTF-8"); logger.addHandler(console);
        try (var ignored = Files.newBufferedWriter(Path.of(args[0]),StandardCharsets.UTF_8)) { }
        FileHandler file = new FileHandler(args[0]); file.setEncoding("UTF-8"); file.setFormatter(new SimpleFormatter()); logger.addHandler(file);
        logger.info("JUL " + sample); file.close(); console.close();
        System.out.println("CHARSET " + java.nio.charset.Charset.defaultCharset());
    }
}
