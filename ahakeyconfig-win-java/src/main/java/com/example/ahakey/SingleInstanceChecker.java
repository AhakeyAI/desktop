package com.example.ahakey;

import java.io.File;
import java.io.RandomAccessFile;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class SingleInstanceChecker {

    private static final Logger logger = LoggerFactory.getLogger(SingleInstanceChecker.class);
    
    private static final String LOCK_FILE_NAME = ".ahakey-studio.lock";
    private static FileLock fileLock;
    private static File lockFile;

    public static boolean isAlreadyRunning() {
        try {
            Path lockDir = Paths.get(System.getProperty("user.home"), ".ahakey");
            if (!Files.exists(lockDir)) {
                Files.createDirectories(lockDir);
            }
            lockFile = new File(lockDir.toFile(), LOCK_FILE_NAME);
            
            if (lockFile.exists()) {
                try {
                    RandomAccessFile raf = new RandomAccessFile(lockFile, "rw");
                    FileChannel channel = raf.getChannel();
                    FileLock testLock = channel.tryLock();
                    if (testLock != null) {
                        testLock.release();
                        channel.close();
                        raf.close();
                        lockFile.delete();
                        logger.info("发现残留的锁文件，已清理");
                    } else {
                        channel.close();
                        raf.close();
                    }
                } catch (Exception e) {
                    lockFile.delete();
                    logger.info("清理残留锁文件失败，强制删除");
                }
            }
            
            RandomAccessFile raf = new RandomAccessFile(lockFile, "rw");
            FileChannel channel = raf.getChannel();
            fileLock = channel.tryLock();
            
            if (fileLock == null) {
                logger.info("检测到已有 AhaKey Studio 实例运行");
                return true;
            }
            
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                try {
                    if (fileLock != null && fileLock.isValid()) {
                        fileLock.release();
                    }
                    channel.close();
                    raf.close();
                    if (lockFile.exists()) {
                        lockFile.delete();
                    }
                } catch (Exception e) {
                    logger.debug("清理锁文件失败: {}", e.getMessage());
                }
            }));
            
            return false;
            
        } catch (Exception e) {
            logger.warn("单实例检测失败: {}", e.getMessage());
            return false;
        }
    }
}