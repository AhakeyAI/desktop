package com.example.ahakey.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.file.*;

/** Pending record is evidence for read-only reconciliation, never an executable write request. */
public class FactoryResetStore {
    public record Target(long generation,String transport,String name,String address,String path) {
        public boolean sameConnection(Target other){return other!=null&&generation==other.generation&&transport.equals(other.transport)&&path.equals(other.path)
                &&(address.isBlank()||other.address.isBlank()||address.equals(other.address));}
        public String display(){return name+" · "+transport+" · "+(!address.isBlank()?address:path.isBlank()?"无硬件序列号":path);}
        public boolean definitelyDifferent(Target other){return other!=null&&transport.equals("BLE")&&other.transport.equals("BLE")&&!address.isBlank()&&!other.address.isBlank()&&!address.equals(other.address);}
        public boolean sameBle(Target other){return other!=null&&transport.equals("BLE")&&other.transport.equals("BLE")&&!address.isBlank()&&address.equals(other.address);}
    }
    public record Pending(int schema,String taskId,Target target,long attempt,String stage){}
    public record Preparation(int schema,String taskId,com.example.ahakey.firmware.DeviceBackup.PcFile runtime,Pending previous){}
    private final Path path;
    private final ObjectMapper json=new ObjectMapper()
            .enable(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES)
            .enable(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_MISSING_CREATOR_PROPERTIES)
            .disable(com.fasterxml.jackson.databind.DeserializationFeature.ACCEPT_FLOAT_AS_INT);
    public static Path defaultPath(){return Path.of(System.getProperty("user.home"),".ahakey","factory-reset-pending.json");}
    public FactoryResetStore(){this(defaultPath());}
    public FactoryResetStore(Path path){this.path=path.toAbsolutePath();}
    public Pending load() throws IOException {
        if(!Files.exists(path))return null;
        Pending p=json.readValue(Files.readAllBytes(path),Pending.class);
        if(p==null||p.schema()!=1||p.taskId()==null||!p.taskId().matches("[0-9a-f-]{36}")||p.target()==null||p.target().name()==null||p.target().address()==null||p.target().path()==null||p.target().transport()==null||!java.util.Set.of("USB","BLE").contains(p.target().transport())||p.attempt()<0||(p.attempt()==0&&!"REJECTED_NOT_STARTED".equals(p.stage()))||p.attempt()>0xffffffffL||p.stage()==null||!java.util.Set.of("LOCAL_PREPARING","SENDING","PREPARED","SENT","COMPLETE_READBACK","REJECTED_NOT_STARTED").contains(p.stage()))throw new IOException("待核实记录损坏，禁止自动关联");
        return p;
    }
    public void save(Pending pending) throws IOException {
        atomicWrite(path,json.writeValueAsBytes(pending));
    }
    private static void atomicWrite(Path destination,byte[] bytes)throws IOException{
        Files.createDirectories(destination.getParent());Path tmp=Files.createTempFile(destination.getParent(),"restore-",".tmp");
        try{
            Files.write(tmp,bytes);
            try(FileChannel c=FileChannel.open(tmp,StandardOpenOption.WRITE)){c.force(true);}
            Files.move(tmp,destination,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
        }finally{Files.deleteIfExists(tmp);}
    }
    private Path preparationPath(){return path.resolveSibling(path.getFileName()+".preparation.json");}
    private Path runtimePath(){return path.resolveSibling("ai-runtime.json");}
    public void beginPreparation(Pending intent,Pending previous)throws IOException{
        var snapshot=com.example.ahakey.firmware.DeviceBackupStore.snapshot(runtimePath());
        atomicWrite(preparationPath(),json.writeValueAsBytes(new Preparation(1,intent.taskId(),snapshot,previous)));
        save(intent);
    }
    private Preparation preparation()throws IOException{
        if(Files.size(preparationPath())>16*1024*1024)throw new IOException("恢复准备备份过大");
        var p=json.readValue(Files.readAllBytes(preparationPath()),Preparation.class);
        if(p==null||p.schema()!=1||p.taskId()==null||!p.taskId().matches("[0-9a-f-]{36}")||p.runtime()==null||p.runtime().base64()==null)throw new IOException("恢复准备备份损坏");
        if(p.runtime().present())try{
            var bytes=java.util.Base64.getDecoder().decode(p.runtime().base64());var node=json.readTree(bytes);
            if(bytes.length>8*1024*1024||node==null||!node.isObject())throw new IOException("运行偏好备份损坏");
        }catch(IllegalArgumentException e){throw new IOException("运行偏好备份损坏",e);}
        return p;
    }
    public void prepareRuntime()throws IOException{
        var p=preparation();
        var node=p.runtime().present()?json.readTree(java.util.Base64.getDecoder().decode(p.runtime().base64())):json.createObjectNode();
        if(!node.isObject())throw new IOException("运行偏好备份无效");
        ((com.fasterxml.jackson.databind.node.ObjectNode)node).put("displayMode","SINGLE");
        writeRuntime(json.writeValueAsBytes(node));
        var verified=com.example.ahakey.firmware.DeviceBackupStore.snapshot(runtimePath());
        if(!verified.present()||!"SINGLE".equals(json.readTree(java.util.Base64.getDecoder().decode(verified.base64())).path("displayMode").asText()))throw new IOException("运行偏好准备未确认");
    }
    protected void writeRuntime(byte[] bytes)throws IOException{atomicWrite(runtimePath(),bytes);}
    public Pending rollbackPreparation()throws IOException{return rollbackPreparation(null);}
    public Pending rollbackPreparation(String taskId)throws IOException{
        if(!Files.exists(preparationPath()))return load();
        var p=preparation();
        var current=load();
        if(taskId!=null&&!taskId.equals(p.taskId()))return current;
        if(current!=null&&!current.taskId().equals(p.taskId())&&!current.equals(p.previous()))throw new IOException("恢复准备身份不匹配");
        restoreRuntime(p.runtime());
        if(p.previous()==null)clear();else save(p.previous());
        clearPreparation();return p.previous();
    }
    protected void restoreRuntime(com.example.ahakey.firmware.DeviceBackup.PcFile saved)throws IOException{
        if(saved.present())atomicWrite(runtimePath(),java.util.Base64.getDecoder().decode(saved.base64()));else Files.deleteIfExists(runtimePath());
    }
    public Pending recoverPreparation()throws IOException{
        Pending p=load();
        // Legacy PREPARED may already have been sent by an older client; never roll it back.
        if(localRecoveryRequired())return rollbackPreparation();
        return p;
    }
    public boolean localRecoveryRequired()throws IOException{
        if(!Files.exists(preparationPath()))return false;
        var p=load();var preparation=preparation();
        return p==null||p.stage().equals("LOCAL_PREPARING")||p.equals(preparation.previous());
    }
    protected void clearPreparation()throws IOException{Files.deleteIfExists(preparationPath());}
    public void finishPreparation()throws IOException{clearPreparation();}
    public void clear() throws IOException {Files.deleteIfExists(path);}
}
