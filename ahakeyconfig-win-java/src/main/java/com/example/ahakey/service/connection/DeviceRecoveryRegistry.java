package com.example.ahakey.service.connection;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.file.*;
import java.util.*;

/** Durable uncertainty, keyed by exact transport identity. Restarting Studio is not device recovery. */
public final class DeviceRecoveryRegistry {
    private static final ObjectMapper JSON=new ObjectMapper();
    private final Path file;
    private final Map<String,Boolean> targets=new HashMap<>();
    private boolean unreadable;
    public DeviceRecoveryRegistry(Path file){
        this.file=file;
        try{if(Files.exists(file))targets.putAll(JSON.readValue(Files.readAllBytes(file),new TypeReference<Map<String,Boolean>>(){}));}
        catch(Exception failure){unreadable=true;}
    }
    public synchronized boolean contains(String target){return unreadable||targets.containsKey(target);}
    public synchronized boolean absenceObserved(String target){return !unreadable&&Boolean.TRUE.equals(targets.get(target));}
    public synchronized void require(String target)throws IOException{
        if(target==null||target.isBlank())return;targets.put(target,false);save();
    }
    public synchronized void observe(String transport,Set<String> present)throws IOException{
        boolean changed=false;
        for(String key:targets.keySet())if(key.startsWith(transport+":")&&!present.contains(key.substring(transport.length()+1))&&!targets.get(key)){targets.put(key,true);changed=true;}
        if(changed)save();
    }
    public synchronized void confirmed(String target)throws IOException{
        if(!absenceObserved(target))throw new IOException("尚未观察到该键盘真实离线");
        Boolean previous=targets.remove(target);try{save();}catch(IOException failure){targets.put(target,previous);throw failure;}
    }
    private void save()throws IOException{
        if(unreadable)throw new IOException("设备恢复记录不可读，写入保持禁用");
        Files.createDirectories(file.toAbsolutePath().getParent());
        Path next=Files.createTempFile(file.toAbsolutePath().getParent(),"recovery-",".tmp");
        try{Files.write(next,JSON.writeValueAsBytes(targets));Files.move(next,file,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);}
        finally{Files.deleteIfExists(next);}
    }
}
