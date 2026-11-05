package com.example.ahakey.service;

import com.example.ahakey.view.CloudAccountDialog;
import com.example.ahakey.platform.windows.WindowsCredentialStore;
import com.sun.net.httpserver.HttpServer;
import com.fasterxml.jackson.databind.ObjectMapper;
import javafx.application.Platform;
import javafx.scene.control.*;
import javafx.stage.*;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Actual dialog handlers/QR terminal rendering; loopback only, synthetic transactions. */
public final class CloudTransactionUiChecks {
    static int checks;static CloudAccountDialog dialog;static CloudAccountManager account;
    static final AtomicBoolean expire=new AtomicBoolean(),unknown=new AtomicBoolean();
    static final AtomicReference<CountDownLatch> entered=new AtomicReference<>(),release=new AtomicReference<>();
    static final AtomicReference<String> blockedPath=new AtomicReference<>();
    static final List<String> codes=new CopyOnWriteArrayList<>();
    static <T>T fx(Callable<T> f)throws Exception{return CloudUiChecks.fx(f);}
    static Stage window(String title){return CloudUiChecks.window(title);}
    static Button button(Stage s,String label){return CloudUiChecks.button(s,label);}
    static boolean text(Stage s,String part){return s.getScene().getRoot().lookupAll(".label").stream().anyMatch(n->n instanceof Label l&&l.getText().contains(part));}
    static void check(boolean ok,String name){checks++;if(!ok)throw new AssertionError(name);}
    static void waitUi(Callable<Boolean> condition)throws Exception{CloudUiChecks.waitUi(condition);checks++;}
    static void login()throws Exception{expire.set(false);account.authenticate("fixture","fake",false,false);fx(()->{if(dialog!=null)dialog.close();dialog=new CloudAccountDialog(null,account,()->{});dialog.show();return null;});}
    static void coupon(String code)throws Exception{fx(()->{button(window("云端账号 · AhaType"),"兑换码").fire();Stage w=window("兑换码");((TextField)w.getScene().getRoot().lookup(".text-field")).setText(code);button(w,"确认兑换").fire();return null;});}
    static void block(String path){blockedPath.set(path);entered.set(new CountDownLatch(1));release.set(new CountDownLatch(1));}
    static void unblock(){blockedPath.set(null);release.get().countDown();}
    static void paidWindow()throws Exception{
        var order=account.createOrder(new CloudAccountManager.Plan("monthly",100));
        fx(()->{var m=CloudAccountDialog.class.getDeclaredMethod("showPayment",CloudAccountManager.Order.class,long.class);m.setAccessible(true);m.invoke(dialog,order,0L);return null;});
    }
    public static void main(String[] args)throws Exception{
        CountDownLatch ready=new CountDownLatch(1);Platform.startup(ready::countDown);ready.await();Platform.setImplicitExit(false);
        var server=HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(),0),0);var network=Executors.newCachedThreadPool();server.setExecutor(network);
        server.createContext("/",x->{try{
            String path=x.getRequestURI().getPath();byte[] request=x.getRequestBody().readAllBytes();String body;
            if(path.endsWith("/redeem"))codes.add(new ObjectMapper().readTree(request).path("code").asText());
            if(path.endsWith(String.valueOf(blockedPath.get()))){entered.get().countDown();release.get().await();}
            if(path.endsWith("/redeem")&&unknown.get()){x.sendResponseHeaders(200,100);x.getResponseBody().write(123);return;}
            if(path.endsWith("/login"))body="{\"code\":0,\"data\":{\"access_token\":\"fixture-token\"}}";
            else if(path.endsWith("/redeem"))body=unknown.get()?"malformed":"{\"code\":0,\"data\":{}}";
            else if(path.endsWith("/native"))body="{\"code\":0,\"data\":{\"out_trade_no\":\"fixture-order\",\"code_url\":\"weixin://wxpay/bizpayurl?pr=fixture\"}}";
            else if(path.endsWith("/order-status"))body="{\"code\":0,\"data\":{\"status\":\"paid\"}}";
            else body=expire.get()?"{\"code\":401}":"{\"code\":0,\"data\":{\"user\":{\"phone\":\"fixture\"},\"policy\":{\"recharge_prices_fen\":{\"monthly\":100}}}}";
            byte[] bytes=body.getBytes(java.nio.charset.StandardCharsets.UTF_8);x.sendResponseHeaders(200,bytes.length);x.getResponseBody().write(bytes);
        }catch(Exception ignored){}finally{x.close();}});server.start();
        var aha=new AhaTypeService(new AhaTypeConfig(Files.createTempDirectory("wd010-transactions-").resolve("account.json"),new WindowsCredentialStore()),HttpClient.newHttpClient(),URI.create("http://localhost:"+server.getAddress().getPort()),Clock.systemUTC());
        account=new CloudAccountManager(aha,Duration.ofMillis(10),Duration.ofSeconds(5));
        try{
            login();block("/redeem");coupon("A");check(entered.get().await(3,TimeUnit.SECONDS),"coupon request entered");
            fx(()->{window("兑换码").hide();button(window("云端账号 · AhaType"),"兑换码").fire();check(button(window("兑换码"),"确认兑换").isDisabled(),"reopen in-flight operation stays disabled");return null;});
            check(codes.equals(List.of("A")),"reopen emits no duplicate A");unblock();waitUi(()->text(window("兑换码"),"兑换成功"));
            fx(()->{window("兑换码").close();button(window("云端账号 · AhaType"),"兑换码").fire();button(window("兑换码"),"兑换新码").fire();check(((TextField)window("兑换码").getScene().getRoot().lookup(".text-field")).getText().isEmpty(),"explicit new operation clears old code");return null;});
            coupon("B");waitUi(()->text(window("兑换码"),"兑换成功"));check(codes.equals(List.of("A","B")),"second confirmed code B sent exactly once");
            // A transport failure is an unknown write outcome and must remain the same operation.
            fx(()->{button(window("兑换码"),"兑换新码").fire();return null;});
            unknown.set(true);coupon("unknown");waitUi(()->text(window("兑换码"),"未确认"));
            fx(()->{window("兑换码").hide();button(window("云端账号 · AhaType"),"兑换码").fire();return null;});check(Collections.frequency(codes,"unknown")==1,"unknown reopen never sends automatically");unknown.set(false);
            login();expire.set(true);coupon("paid-coupon");waitUi(()->text(window("兑换码"),"兑换成功")&&text(window("兑换码"),"请重新登录"));
            fx(()->{check(button(window("云端账号 · AhaType"),"登录")!=null&&button(window("兑换码"),"确认兑换").isDisabled(),"redeem success then401 finishes operation and returns main to login");return null;});
            login();expire.set(true);paidWindow();waitUi(()->text(window("微信扫码支付"),"支付成功")&&text(window("微信扫码支付"),"请重新登录"));
            fx(()->{check(button(window("云端账号 · AhaType"),"登录")!=null,"paid then401 returns main to login while preserving payment terminal");return null;});
            for(boolean payment:new boolean[]{false,true}){
                login();block("/users/me");if(payment)paidWindow();else coupon("switch-account");check(entered.get().await(3,TimeUnit.SECONDS),"successful operation refresh is blocked");
                var old=aha.session();account.logout();blockedPath.set(null);account.authenticate("replacement","fake",false,false);release.get().countDown();
                Thread.sleep(150);fx(()->{Stage w=window(payment?"微信扫码支付":"兑换码");check(!text(w,payment?"支付成功":"兑换成功"),"old success cannot update after explicit account switch");return null;});check(!aha.current(old)&&account.isLoggedIn(),"replacement account retained");
            }
            for(boolean payment:new boolean[]{false,true})for(boolean switchAccount:new boolean[]{false,true}){
                login();block("/users/me");if(payment)paidWindow();else coupon("concurrent-401");check(entered.get().await(3,TimeUnit.SECONDS),"transaction refresh waits before competing401");
                blockedPath.set(null);expire.set(true);check(account.refreshProfile()!=null&&!account.isLoggedIn(),"other request invalidates same account first");
                if(switchAccount){account.logout();expire.set(false);account.authenticate("replacement","fake",false,false);expire.set(true);}
                release.get().countDown();
                if(!switchAccount){waitUi(()->text(window(payment?"微信扫码支付":"兑换码"),payment?"支付成功":"兑换成功")&&text(window(payment?"微信扫码支付":"兑换码"),"请重新登录"));}
                else{Thread.sleep(150);fx(()->{check(!text(window(payment?"微信扫码支付":"兑换码"),payment?"支付成功":"兑换成功"),"explicit switch severs server-expiry delivery chain");return null;});check(account.isLoggedIn(),"late401 does not invalidate replacement login");}
            }
            // Competing401 arrives before the write/status success response itself, not during refresh.
            for(boolean payment:new boolean[]{false,true})for(boolean switchAccount:new boolean[]{false,true}){
                login();block(payment?"/order-status":"/redeem");if(payment)paidWindow();else coupon("response-after-401");
                check(entered.get().await(3,TimeUnit.SECONDS),"transaction success response blocked before competing401");
                blockedPath.set(null);expire.set(true);check(account.refreshProfile()!=null&&!account.isLoggedIn(),"same account expires before transaction response");
                if(switchAccount){account.logout();expire.set(false);account.authenticate("replacement","fake",false,false);}
                release.get().countDown();
                if(!switchAccount){waitUi(()->text(window(payment?"微信扫码支付":"兑换码"),payment?"支付成功":"兑换成功")&&text(window(payment?"微信扫码支付":"兑换码"),"请重新登录"));}
                else{Thread.sleep(150);fx(()->{check(!text(window(payment?"微信扫码支付":"兑换码"),payment?"支付成功":"兑换成功"),"explicit switch suppresses old transaction response");return null;});check(account.isLoggedIn(),"replacement survives late transaction success");}
            }
            System.out.println("PASS CloudTransactionUiChecks "+checks+" checks; actual coupon and QR windows, loopback only");
        }finally{if(release.get()!=null)release.get().countDown();fx(()->{if(dialog!=null)dialog.close();return null;});account.close();server.stop(0);network.shutdownNow();Platform.exit();}
    }
}
