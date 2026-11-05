package com.example.ahakey.service;

import com.example.ahakey.view.CloudAccountDialog;
import com.example.ahakey.platform.windows.WindowsCredentialStore;
import com.sun.net.httpserver.HttpServer;
import javafx.application.Platform;
import javafx.scene.control.*;
import javafx.stage.*;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.time.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Real JavaFX handlers and loopback HTTP; all credentials and coupons are synthetic. */
public final class CloudUiChecks {
    static int checks;
    static void check(boolean ok,String label){checks++;if(!ok)throw new AssertionError(label);}
    static <T>T fx(Callable<T> action)throws Exception{FutureTask<T> f=new FutureTask<>(action);Platform.runLater(f);return f.get(10,TimeUnit.SECONDS);}
    static Stage window(String title){return (Stage)Window.getWindows().stream().filter(w->w instanceof Stage s&&s.getTitle().equals(title)&&s.isShowing()).findFirst().orElseThrow();}
    static Button button(Stage s,String text){return (Button)s.getScene().getRoot().lookupAll(".button").stream().filter(n->n instanceof Button b&&b.getText().equals(text)).findFirst().orElseThrow();}
    static void waitUi(Callable<Boolean> condition)throws Exception{long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);while(!fx(condition)&&System.nanoTime()<end)Thread.sleep(20);check(fx(condition),"UI completion");}
    public static void main(String[] args)throws Exception{
        CountDownLatch ready=new CountDownLatch(1);Platform.startup(ready::countDown);ready.await();Platform.setImplicitExit(false);
        AtomicBoolean expired=new AtomicBoolean(),badLogin=new AtomicBoolean();AtomicInteger redeemed=new AtomicInteger();
        var server=HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(),0),0);
        server.createContext("/",x->{String path=x.getRequestURI().getPath();x.getRequestBody().readAllBytes();String body;
            if(path.endsWith("/login"))body=badLogin.get()?"{\"code\":400}":"{\"code\":0,\"data\":{\"access_token\":\"fixture\"}}";
            else if(path.endsWith("/redeem")){redeemed.incrementAndGet();body="{\"code\":400}";}
            else body=expired.get()?"{\"code\":401}":"{\"code\":0,\"data\":{\"user\":{\"phone\":\"fixture\"}}}";
            byte[] bytes=body.getBytes(java.nio.charset.StandardCharsets.UTF_8);x.sendResponseHeaders(200,bytes.length);x.getResponseBody().write(bytes);x.close();});server.start();
        var aha=new AhaTypeService(new AhaTypeConfig(Files.createTempDirectory("wd010-ui-").resolve("account.json"),new WindowsCredentialStore()),HttpClient.newHttpClient(),URI.create("http://localhost:"+server.getAddress().getPort()),Clock.systemUTC());
        var account=new CloudAccountManager(aha);account.authenticate("fixture","fake",false,false);
        var dialog=fx(()->{var d=new CloudAccountDialog(null,account,()->{});d.show();return d;});
        ExecutorService worker=Executors.newSingleThreadExecutor();var field=CloudAccountDialog.class.getDeclaredField("worker");field.setAccessible(true);((ExecutorService)field.get(dialog)).shutdownNow();field.set(dialog,worker);
        try{
            expired.set(true);fx(()->{button(window("云端账号 · AhaType"),"刷新账号").fire();return null;});
            waitUi(()->!window("云端账号 · AhaType").getScene().getRoot().isDisabled());
            fx(()->{var s=window("云端账号 · AhaType");check(!account.isLoggedIn()&&button(s,"登录")!=null,"401 profile returns to login page");for(var n:s.getScene().getRoot().lookupAll(".text-field"))if(n instanceof PasswordField p)p.setText("preserved-secret");else if(n instanceof TextField t)t.setText("preserved-phone");badLogin.set(true);button(s,"登录").fire();return null;});
            waitUi(()->!window("云端账号 · AhaType").getScene().getRoot().isDisabled());
            fx(()->{check(window("云端账号 · AhaType").getScene().getRoot().lookupAll(".text-field").stream().anyMatch(n->n instanceof PasswordField p&&p.getText().equals("preserved-secret")),"failed login preserves typed password");return null;});
            expired.set(false);badLogin.set(false);account.authenticate("fixture","fake",false,false);
            fx(()->{window("云端账号 · AhaType").hide();dialog.show();button(window("云端账号 · AhaType"),"兑换码").fire();var s=window("兑换码");((TextField)s.getScene().getRoot().lookup(".text-field")).setText("fake-coupon");button(s,"确认兑换").fire();return null;});
            waitUi(()->!button(window("兑换码"),"确认兑换").isDisabled());check(redeemed.get()==1,"explicit coupon failure is retryable, no automatic retry");
            CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);worker.submit(()->{entered.countDown();try{release.await();}catch(InterruptedException e){Thread.currentThread().interrupt();}});entered.await();
            fx(()->{button(window("兑换码"),"确认兑换").fire();return null;});account.logout();account.authenticate("other","fake",false,false);release.countDown();worker.submit(()->{}).get(10,TimeUnit.SECONDS);
            check(redeemed.get()==1&&account.redeemStatus().isEmpty(),"queued UI coupon is never sent to replacement account");
            System.out.println("PASS CloudUiChecks "+checks+" checks; actual login/refresh/coupon handlers and loopback HTTP");
        }finally{fx(()->{dialog.close();return null;});account.close();worker.shutdownNow();server.stop(0);Platform.exit();}
    }
}
