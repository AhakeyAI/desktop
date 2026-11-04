package com.example.ahakey.service;

import java.io.*;
import java.net.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicReference;

/** Real TCP listener/client checks with production adapter and memory-only device wire. */
public final class KimiRoutingChecks {
    static int checks;
    static void check(String name,boolean value){if(!value)throw new AssertionError(name);checks++;System.out.println("PASS "+name);}
    static byte[] query(Socket s,int type)throws Exception {
        s.getOutputStream().write(new byte[]{(byte)type,0,0});s.getOutputStream().flush();
        DataInputStream in=new DataInputStream(s.getInputStream());
        byte[] h=new byte[3];in.readFully(h);int size=(h[1]&255)|((h[2]&255)<<8);return in.readNBytes(size);
    }
    static Socket client(int port)throws Exception{Socket s=new Socket("127.0.0.1",port);s.setSoTimeout(1000);return s;}
    public static void main(String[] args)throws Exception {
        if(args.length>0&&args[0].equals("environment")){
            try {System.out.println("ENDPOINT "+BleManager.fromEnvironment(KimiConsumerFixture.CALLBACK).bridgeEndpoint());}
            catch(IllegalArgumentException e){System.out.println("ENDPOINT REJECTED "+e.getMessage());}return;
        }
        check("default raw BLE endpoint 9001",new BleManager(KimiConsumerFixture.CALLBACK).bridgeEndpoint().getPort()==9001);
        for(String p:new String[]{"9000","0","65536","-1","+9001","bad","1.0","999999999999"}){
            boolean reject=false;try{BleManager.parseBridgePort(p);}catch(IllegalArgumentException e){reject=true;}check("reject raw endpoint "+p,reject);
        }
        check("environment parser default",BleManager.parseBridgePort(null)==9001&&BleManager.parseBridgePort(" ")==9001);
        check("custom endpoint parser",BleManager.parseBridgePort(" 19001 ")==19001&&BleManager.parseBridgePort("65535")==65535);
        check("host override preserved",new BleManager("192.0.2.55",19001,KimiConsumerFixture.CALLBACK).bridgeEndpoint().getHostString().equals("192.0.2.55"));
        var wire=new KimiConsumerFixture.Wire();var bridge=new KimiAhaKeyBridge(wire,0);
        try {
            bridge.start();int port=KimiConsumerFixture.port(bridge);
            for(boolean usb:new boolean[]{true,false}) {
                wire.activate(usb,0,false,0);bridge.connectionChanged();
                check("same adapter retained "+usb,KimiConsumerFixture.port(bridge)==port);
                try(Socket s=client(port)){check("AUTO status "+usb,query(s,3)[0]==1);check("AUTO info "+usb,query(s,4)[6]==0);}
                wire.activate(usb,3,false,0);
                try(Socket s=client(port)){check("custom physical up defers "+usb,query(s,3)[0]==0);}
                wire.activate(usb,0,false,0);
                try(Socket s=client(port)){
                    check("A status ready "+usb,query(s,3)[0]==1);int reads=wire.reads;
                    wire.activate(!usb,0,false,0); // same address/session, replacement keyboard before info
                    check("old client cannot approve B "+usb,query(s,4).length==0);
                    check("old query never reads B bindings "+usb,wire.reads==reads);
                }
                KimiConsumerFixture.field(wire,"isConnected",false);wire.getCachedStatus().setConnected(false);bridge.connectionChanged();
                check("disconnected endpoint still reserved "+usb,KimiConsumerFixture.port(bridge)==port);
                try(Socket s=client(port)){check("disconnected native unavailable "+usb,query(s,3)[0]==0);}
                boolean occupied=false;try(ServerSocket other=new ServerSocket()){other.bind(new InetSocketAddress("127.0.0.1",port));}catch(IOException expected){occupied=true;}
                check("no second listener during disconnect "+usb,occupied);
            }
            wire.activate(false,0,false,0);
            try(Socket s=client(port)){
                check("pre-maintenance status",query(s,3)[0]==1);
                wire.maintenance().requestExit(null);
                check("maintenance cannot reuse approved target",query(s,4).length==0);
            }
            check("maintenance keeps native endpoint",KimiConsumerFixture.port(bridge)==port);
            bridge.close();check("close releases endpoint",KimiConsumerFixture.port(bridge)==0);
            try(ServerSocket replacement=new ServerSocket()){replacement.setReuseAddress(true);replacement.bind(new InetSocketAddress("127.0.0.1",port));check("port can be owned after exit",true);}
        }finally{bridge.close();}
        try(ServerSocket occupied=new ServerSocket(0,10,InetAddress.getLoopbackAddress())) {
            var collision=new KimiAhaKeyBridge(new KimiConsumerFixture.Wire(),occupied.getLocalPort());AtomicReference<String> issue=new AtomicReference<>();collision.setProblemHandler(issue::set);
            collision.start();check("occupied port does not double bind",KimiConsumerFixture.port(collision)==0);
            check("collision explicitly warns unsafe native routing",issue.get()!=null&&issue.get().contains("审批状态无法确认"));
            occupied.close();collision.connectionChanged();
            check("explicit retry obtains released endpoint",KimiConsumerFixture.port(collision)>0);
            check("successful retry clears persistent warning","".equals(issue.get()));collision.close();
        }
        var transitionWire=new KimiConsumerFixture.Wire();var transitionBridge=new KimiAhaKeyBridge(transitionWire,0);
        try{
            transitionBridge.start();int port=KimiConsumerFixture.port(transitionBridge);transitionBridge.prepareForConnection();
            try(Socket s=client(port)){check("prepared old target unavailable",query(s,3)[0]==0);}
            transitionWire.activate(false,0,false,0);transitionBridge.connectionChanged();
            try(Socket s=client(port)){check("new generation may approve",query(s,3)[0]==1&&query(s,4)[6]==0);}
        }finally{transitionBridge.close();}
        Path root=Path.of(System.getProperty("ahakey.test.sourceRoot"));
        String top=Files.readString(root.resolve("src/main/java/com/example/ahakey/view/TopBar.java"));
        check("TopBar routes both control/probe to raw endpoint",top.split(java.util.regex.Pattern.quote("controller.getBleManager().bridgeEndpoint()"),-1).length==3&&!top.contains("new InetSocketAddress(\"127.0.0.1\", 9000)"));
        System.out.println("PASS "+checks+" Kimi routing checks; no live keyboard, bridge process, native input or installed hooks");
    }
}
