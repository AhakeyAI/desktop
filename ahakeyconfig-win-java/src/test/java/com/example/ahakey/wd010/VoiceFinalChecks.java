package com.example.ahakey.service;

import com.example.ahakey.platform.windows.WindowsCredentialStore;
import com.sun.net.httpserver.HttpServer;
import java.net.*;
import java.net.http.HttpClient;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Actual AhaTypeService -> VoiceInputManager -> captured output, no speech engine/microphone/keys. */
public final class VoiceFinalChecks {
    private static int checks;
    private static void check(boolean ok,String label){checks++;if(!ok)throw new AssertionError(label);}
    static final class Speech extends SpeechService {
        Consumer<String> finalText,partial;boolean busy;
        public void initialize(){}public void setErrorCallback(Consumer<String> callback){}
        public void startListening(Consumer<String> p,Consumer<String> f){partial=p;finalText=f;busy=true;}
        public void stopListening(){}public boolean isBusy(){return busy;}public void release(){busy=false;}
        void finish(String text){busy=false;finalText.accept(text);}
    }
    public static void main(String[] args)throws Exception{
        AtomicReference<CountDownLatch> entered=new AtomicReference<>(),release=new AtomicReference<>();AtomicReference<String> response=new AtomicReference<>();AtomicInteger requests=new AtomicInteger();
        HttpServer server=HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(),0),0);ExecutorService http=Executors.newCachedThreadPool();server.setExecutor(http);
        server.createContext("/",exchange->{try{requests.incrementAndGet();exchange.getRequestBody().readAllBytes();entered.get().countDown();release.get().await();byte[] bytes=response.get().getBytes(java.nio.charset.StandardCharsets.UTF_8);exchange.sendResponseHeaders(200,bytes.length);exchange.getResponseBody().write(bytes);}catch(Exception ignored){}finally{exchange.close();}});server.start();
        try{
            for(String scenario:List.of("once","stop","next","shutdown","logout-success","logout-error","logout-expired","expired-current")){
                var aha=new AhaTypeService(new AhaTypeConfig(Files.createTempDirectory("wd010-voice-").resolve("account.json"),new WindowsCredentialStore()),HttpClient.newHttpClient(),URI.create("http://localhost:"+server.getAddress().getPort()),Clock.systemUTC());
                aha.authenticate(aha.beginAuthentication(),"fixture-token","fixture","",false);aha.setEnabled(true);
                response.set(scenario.contains("error")?"invalid":scenario.contains("expired")?"{\"code\":500,\"data\":401}":"{\"code\":\"200\",\"data\":{\"text\":\"整理文本\"}}");entered.set(new CountDownLatch(1));release.set(new CountDownLatch(1));
                Speech speech=new Speech();List<String> output=new CopyOnWriteArrayList<>(),preview=new CopyOnWriteArrayList<>();ExecutorService worker=Executors.newSingleThreadExecutor();
                VoiceInputManager manager=new VoiceInputManager(()->speech,()->null,output::add,aha::process,worker);manager.initialize();manager.startVoiceInput(preview::add,preview::add);
                int prior=requests.get();manager.startRecording();speech.partial.accept("partial");check(output.isEmpty()&&requests.get()==prior,"partials do not process or inject");manager.stopRecording();speech.finish("原文");
                check(entered.get().await(5,TimeUnit.SECONDS),"cloud request entered");speech.finish("duplicate");
                if(scenario.equals("stop"))manager.stopVoiceInput();if(scenario.equals("next"))manager.startRecording();if(scenario.equals("shutdown"))manager.shutdown();if(scenario.startsWith("logout"))aha.logout();
                release.get().countDown();worker.submit(()->{}).get(5,TimeUnit.SECONDS);
                check(requests.get()==prior+1,"one final yields one cloud request");
                if(scenario.equals("once"))check(output.equals(List.of("整理文本")),"one processed output");
                else if(scenario.equals("expired-current"))check(output.equals(List.of("原文")),"server expiry falls back original for current recording");
                else check(output.isEmpty(),"stale/cancelled pipeline never injects: "+scenario);
                manager.shutdown();worker.shutdownNow();
            }
        }finally{server.stop(0);http.shutdownNow();}
        System.out.println("PASS VoiceFinalChecks "+checks+" checks; actual cloud-final pipeline, synthetic loopback HTTP and captured output");
    }
}
