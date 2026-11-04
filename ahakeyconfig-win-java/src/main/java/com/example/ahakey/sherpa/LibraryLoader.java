package com.example.ahakey.sherpa;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

public class LibraryLoader {
    private static final Logger logger = LoggerFactory.getLogger(LibraryLoader.class);
    private static boolean loaded = false;
    private static String nativeLibDir = null;
    
    public static synchronized void load() {
        if (loaded) {
            return;
        }
        
        try {
            extractNativeLibs();
            
            System.load(nativeLibDir + File.separator + "onnxruntime.dll");
            logger.info("onnxruntime.dll 加载成功");
            
            System.load(nativeLibDir + File.separator + "sherpa-onnx-jni.dll");
            logger.info("sherpa-onnx-jni.dll 加载成功");
            
            loaded = true;
            logger.info("Sherpa-ONNX JNI 库加载成功");
        } catch (Exception e) {
            logger.error("加载 Sherpa-ONNX JNI 库失败", e);
            throw new RuntimeException("加载 Sherpa-ONNX JNI 库失败", e);
        }
    }
    
    private static void extractNativeLibs() throws Exception {
        File tempDir = File.createTempFile("sherpa-onnx", "native");
        tempDir.delete();
        tempDir.mkdirs();
        tempDir.deleteOnExit();
        
        nativeLibDir = tempDir.getAbsolutePath();
        
        extractLib("onnxruntime.dll");
        extractLib("onnxruntime_providers_shared.dll");
        extractLib("sherpa-onnx-jni.dll");
        
        logger.info("Native 库提取到: {}", nativeLibDir);
    }
    
    private static void extractLib(String libName) throws Exception {
        String resourcePath = "/sherpa-onnx/native/win-x64/" + libName;
        InputStream inputStream = LibraryLoader.class.getResourceAsStream(resourcePath);
        
        if (inputStream == null) {
            inputStream = LibraryLoader.class.getClassLoader().getResourceAsStream(resourcePath);
        }
        
        if (inputStream == null) {
            throw new RuntimeException("找不到 JNI 库资源: " + resourcePath);
        }
        
        File outputFile = new File(nativeLibDir, libName);
        try (OutputStream outputStream = new FileOutputStream(outputFile)) {
            byte[] buffer = new byte[8192];
            int bytesRead;
            while ((bytesRead = inputStream.read(buffer)) != -1) {
                outputStream.write(buffer, 0, bytesRead);
            }
        }
        inputStream.close();
        
        logger.debug("提取库文件: {} -> {}", libName, outputFile.getAbsolutePath());
    }
    
    public static boolean isLoaded() {
        return loaded;
    }
}
