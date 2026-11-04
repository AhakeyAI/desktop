package com.example.ahakey.service;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.protocol.AhaKeyProtocol;
import java.io.*;
import java.lang.reflect.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Actual Kimi adapter + BleManager parser/requests; USB and BLE wire endpoints are memory only. */
public final class KimiConsumerFixture {
    static final BleManager.BleCallback CALLBACK = new BleManager.BleCallback() {
        public void onConnected() {} public void onDisconnected() {} public void onStatusReceived(DeviceStatus s) {} public void onError(String s) {}
    };
    static void field(Object object, String name, Object value) throws Exception {
        Field f=BleManager.class.getDeclaredField(name);f.setAccessible(true);f.set(object,value);
    }
    static final class Wire extends BleManager {
        volatile boolean usb=true, unknown;
        volatile int binding, delayMillis;
        int reads;
        Wire() throws Exception {
            super(CALLBACK);
            field(this,"usbTransport",new UsbHidTransport() {
                public boolean isOpen(){return usb;}
                public void open(java.util.function.Consumer<byte[]> c){throw new AssertionError("No real USB");}
                public void sendCommand(byte[] c){respond(c);}
                public void sendData(byte[] c){throw new AssertionError("No upload");}
                public void close(){}
            });
            field(this,"outputStream",new ByteArrayOutputStream(){
                public synchronized void write(byte[] b,int off,int len){respond(Arrays.copyOfRange(b,off+3,off+len));}
            });
            activate(true,0,false,0);
        }
        protected boolean isUsbDevicePresent(){return false;}
        public void connect(){throw new AssertionError("No real connect");}
        void activate(boolean usb,int binding,boolean unknown,int delay) throws Exception {
            this.usb=usb;this.binding=binding;this.unknown=unknown;this.delayMillis=0;
            field(this,"connectionGeneration",connectionGeneration()+1);
            field(this,"isConnected",true);getCachedStatus().setConnected(true);getCachedStatus().clearFirmwareIdentity();
            readFirmwareCatalogKey();this.delayMillis=delay;
        }
        void respond(byte[] q) {
            long generation=connectionGeneration();int cmd=q[2]&255;byte[] data;
            if(cmd==0x9F)data=("\0x1-c582-hw1-p1-1.0.1-r001").getBytes(StandardCharsets.US_ASCII);
            else if(cmd==0)data=new byte[]{100,0,1,1,0,0,0,35};
            else if(cmd==0x97){reads++;data=unknown?new byte[]{0,0}:new byte[]{0,0,2,(byte)binding,0,1,0};}
            else throw new AssertionError("Unexpected write "+cmd);
            try {
                if(delayMillis>0)Thread.sleep(delayMillis);
                Method m=BleManager.class.getDeclaredMethod("onSessionNotify",long.class,byte[].class);m.setAccessible(true);
                m.invoke(this,generation,AhaKeyProtocol.buildFrame((byte)cmd,data));
            }catch(Exception e){throw new AssertionError(e);}
        }
    }
    static int port(KimiAhaKeyBridge bridge) throws Exception {
        Field f=KimiAhaKeyBridge.class.getDeclaredField("session");f.setAccessible(true);Object session=f.get(bridge);
        if(session==null)return 0;
        f=session.getClass().getDeclaredField("listener");f.setAccessible(true);return ((ServerSocket)f.get(session)).getLocalPort();
    }
    public static void main(String[] args)throws Exception {
        Wire wire=new Wire();KimiAhaKeyBridge bridge=new KimiAhaKeyBridge(wire,0);
        try(BufferedReader input=new BufferedReader(new InputStreamReader(System.in))){
            String line;
            while((line=input.readLine())!=null&&!line.equals("quit")){
                if(line.endsWith("disconnected")){field(wire,"isConnected",false);wire.getCachedStatus().setConnected(false);}
                else if(line.equals("prepare")){bridge.prepareForConnection();}
                else if(line.equals("maintenance")){wire.maintenance().requestExit(null);}
                else {
                    boolean usb=line.startsWith("usb");int binding=line.contains("manual")?1:line.contains("custom")?3:0;
                    wire.activate(usb,binding,line.contains("unknown"),line.contains("slow")?220:line.contains("delayed")?50:0);
                }
                bridge.connectionChanged();
                System.out.println("FIXTURE_READY "+line+" "+port(bridge));System.out.flush();
            }
        }finally{bridge.close();}
    }
}
