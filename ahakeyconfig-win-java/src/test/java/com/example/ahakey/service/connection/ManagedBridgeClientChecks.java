package com.example.ahakey.service.connection;

import com.fasterxml.jackson.databind.*;
import java.io.*;
import java.net.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Real loopback framing plus blocked-stream fixtures; never starts the bridge or a device. */
public final class ManagedBridgeClientChecks {
    static final ObjectMapper JSON=new ObjectMapper();
    static int checks;
    public static final class StubbornProcess extends Process {
        public volatile boolean alive=true;
        public int destroys;
        public OutputStream getOutputStream(){return OutputStream.nullOutputStream();}
        public InputStream getInputStream(){return InputStream.nullInputStream();}
        public InputStream getErrorStream(){return InputStream.nullInputStream();}
        public int waitFor(){if(alive)throw new IllegalStateException("still alive");return 0;}
        public boolean waitFor(long timeout,TimeUnit unit){return !alive;}
        public int exitValue(){if(alive)throw new IllegalThreadStateException();return 0;}
        public void destroy(){destroys++;}
        public Process destroyForcibly(){destroys++;return this;}
        public boolean isAlive(){return alive;}
    }
    static void check(boolean value,String name){if(!value)throw new AssertionError(name);checks++;}
    static JsonNode read(Socket s)throws Exception{
        DataInputStream in=new DataInputStream(s.getInputStream());check(in.readUnsignedByte()==0x10,"request envelope");
        int n=in.readUnsignedByte()|in.readUnsignedByte()<<8;return JSON.readTree(in.readNBytes(n));
    }
    static void send(Socket s,int type,JsonNode node)throws Exception{
        byte[] b=JSON.writeValueAsBytes(node);var out=s.getOutputStream();out.write(type);out.write(b.length&255);out.write(b.length>>8);out.write(b);out.flush();
    }
    static class BlockedSocket extends Socket {
        final CountDownLatch entered=new CountDownLatch(1),released=new CountDownLatch(1);
        volatile boolean shut;
        @Override public void setTcpNoDelay(boolean ignored){}
        @Override public boolean isClosed(){return shut;}
        @Override public void close(){shut=true;released.countDown();}
        void block()throws IOException{try{released.await();}catch(InterruptedException e){Thread.currentThread().interrupt();}throw new IOException("closed");}
        @Override public InputStream getInputStream(){return new InputStream(){public int read()throws IOException{block();return -1;}};}
        @Override public OutputStream getOutputStream(){return new OutputStream(){public void write(int b)throws IOException{entered.countDown();block();}};}
    }
    public static void main(String[] args)throws Exception{
        try(var client=new ManagedBridgeClient();var listener=new ServerSocket(0,1,InetAddress.getLoopbackAddress());var local=new Socket("127.0.0.1",listener.getLocalPort());var peer=listener.accept()){
            client.attach(local);
            var pool=Executors.newFixedThreadPool(2);
            try{
                var first=pool.submit(()->client.request("first",1000));JsonNode a=read(peer);
                var second=pool.submit(()->client.request("second",1000));JsonNode b=read(peer);
                send(peer,0x90,ManagedBridgeClient.fields().put("version",1).put("bridgeInstanceId","one").put("requestId",b.path("requestId").asText()).put("ok",true).put("value",2));
                send(peer,0x90,ManagedBridgeClient.fields().put("version",1).put("bridgeInstanceId","one").put("requestId",a.path("requestId").asText()).put("ok",true).put("value",1));
                check(first.get().path("value").asInt()==1 && second.get().path("value").asInt()==2,"correlation survives out of order replies");
            }finally{pool.shutdownNow();}
        }
        try(var client=new ManagedBridgeClient()){
            BlockedSocket socket=new BlockedSocket();client.attach(socket);long at=System.nanoTime();
            try{client.request("blocked",120);throw new AssertionError("deadline missing");}catch(IOException expected){}
            check(TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-at)<800,"blocked write has total deadline");
            check(socket.shut,"deadline closes owning socket");
        }
        try(var client=new ManagedBridgeClient();var listener=new ServerSocket(0,2,InetAddress.getLoopbackAddress())){
            var entered=new CountDownLatch(1);var release=new CountDownLatch(1);var delivered=new AtomicInteger();
            client.onEvent(event->{if(event.path("event").asText().equals("hold")){entered.countDown();try{release.await();}catch(InterruptedException e){Thread.currentThread().interrupt();}}else delivered.incrementAndGet();});
            try(var a=new Socket("127.0.0.1",listener.getLocalPort());var pa=listener.accept();var b=new Socket("127.0.0.1",listener.getLocalPort());var pb=listener.accept()){
                client.attach(a);send(pa,0x91,ManagedBridgeClient.fields().put("version",1).put("eventSeq",1).put("event","hold"));
                check(entered.await(1,TimeUnit.SECONDS),"event queue deliberately held");
                pa.close();Thread.sleep(30);client.attach(b);release.countDown();Thread.sleep(70);
                check(delivered.get()==0,"queued old disconnect cannot reach new connection");
                send(pb,0x91,ManagedBridgeClient.fields().put("version",1).put("eventSeq",1).put("event","new"));
                long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(1);while(delivered.get()==0&&System.nanoTime()<end)Thread.sleep(5);
                check(delivered.get()==1,"new connection owns independent event sequence");
            }finally{release.countDown();}
        }
        try(var client=new ManagedBridgeClient()){
            BlockedSocket old=new BlockedSocket();client.attach(old);Object identity=client.ownerIdentity();old.close();
            BlockedSocket replacement=new BlockedSocket();client.attach(replacement);
            client.releaseSession(identity,ManagedBridgeClient.fields().put("sessionId","A"));
            check(!replacement.shut,"failed old release cannot close new bridge connection");
            client.releaseSession(identity,ManagedBridgeClient.fields().put("sessionId","A"));
            check(!replacement.shut,"retired release is repeatable, no exceptional barrier");
        }
        System.out.println("PASS "+checks+" managed IPC behavior checks; loopback only");
    }
}
