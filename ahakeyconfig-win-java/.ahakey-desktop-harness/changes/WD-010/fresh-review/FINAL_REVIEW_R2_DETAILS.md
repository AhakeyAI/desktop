# WD-010 R2 独立复审定向证据

本文件附属于 FINAL_REVIEW_R2.json；冻结包 dac7f24c2375abd670d2d698eceb179cf9d9fa0a3c07170878013039dc008c51，结论 FAIL。

## 复现结论

提交的61项恢复准备、47项云端交易测试独立重跑通过。新增最终FX队列时序在兑换和付款窗口均复现终态丢失。仅本地合成账号、loopback HTTP、真实JavaFX；没有线上账户或设备动作。

成功与资料刷新200已经完成并排入UI队列，后台执行器已空闲；随后另一请求401使原session映射到合法server-expired delivery。释放FX后两窗口仍处于进行中。不要把测试中的受控FX阻塞当成业务前提：它只把真实runLater异步窗口放大为可重复顺序。

## 精确运行身份

```json
[
  {
    "suite": "RestorePreparationChecks",
    "command": [
      "D:/jdk-17.0.19.10-hotspot/bin/java.exe",
      "-Dfile.encoding=UTF-8",
      "-Duser.home=C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\home-RestorePreparationChecks",
      "-Djava.io.tmpdir=C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_",
      "-cp",
      "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\test-classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\lib\\*",
      "com.example.ahakey.wd010.CheckProcess",
      "com.example.ahakey.wd010.RestorePreparationChecks"
    ],
    "cwd": "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_",
    "exit_code": 0,
    "log": "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\RestorePreparationChecks.log",
    "sha256": "2145f3b9154ed53d834f40b1897608578f69d00688f87a12eeddd122a6fb0589"
  },
  {
    "suite": "CloudTransactionUiChecks",
    "command": [
      "D:/jdk-17.0.19.10-hotspot/bin/java.exe",
      "-Dfile.encoding=UTF-8",
      "-Duser.home=C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\home-CloudTransactionUiChecks",
      "-Djava.io.tmpdir=C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_",
      "-cp",
      "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\test-classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\lib\\*",
      "com.example.ahakey.wd010.CheckProcess",
      "com.example.ahakey.service.CloudTransactionUiChecks"
    ],
    "cwd": "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_",
    "exit_code": 0,
    "log": "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\CloudTransactionUiChecks.log",
    "sha256": "0dbcea5746b6caa0ba011c5ec9feb388875ea9875ff09657420bcdbdacced5ec"
  },
  {
    "compile_command": [
      "D:/jdk-17.0.19.10-hotspot/bin/javac.exe",
      "-encoding",
      "UTF-8",
      "-cp",
      "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\test-classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\lib\\*",
      "-d",
      "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\review-classes",
      "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\QueuedDeliveryChecks.java"
    ],
    "command": [
      "D:/jdk-17.0.19.10-hotspot/bin/java.exe",
      "-Dfile.encoding=UTF-8",
      "-Duser.home=C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\home-queued-delivery",
      "-Djava.io.tmpdir=C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_",
      "-cp",
      "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\review-classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\test-classes;C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\lib\\*",
      "com.example.ahakey.wd010.CheckProcess",
      "com.example.ahakey.service.QueuedDeliveryChecks"
    ],
    "cwd": "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_",
    "exit_code": 1,
    "log": "C:\\Users\\20825\\AppData\\Local\\Temp\\wd010-fresh-r2-ijewsc9_\\QueuedDeliveryChecks.log",
    "sha256": "ae098d7d75f1c3bfe480915d9f466396b81bb570bf7f8144e03deea07d470c82",
    "fixture_sha256": "143a5d0c07f5c44053de89fd22983fc72c5c18716a5e18fe7dced2ea8f77ad13"
  }
]
```

类和依赖快照清单：`C:\Users\20825\AppData\Local\Temp\wd010-fresh-r2-ijewsc9_\SNAPSHOT.json`，SHA256 `2aa79455b789b473c212be5e842908b22c18ca24a659366cbf72f8112e230d12`。生产类未重新编译；临时目录隔离防止与并行构建互相覆盖。

## 定向失败日志（原始文件SHA见上方）

```text
11月 05, 2026 1:15:42 下午 com.sun.javafx.application.PlatformImpl startup
警告: Unsupported JavaFX configuration: classes were loaded from 'unnamed module @377dca04'
coupon success callback was queued; server expiry mapping valid; terminalShown=false; labels= | 当前账号：fixture | 正在兑换…
payment success callback was queued; server expiry mapping valid; terminalShown=false; labels= | 金额：1.00 元（所选套餐报价） | 正在查询付款结果…
java.lang.AssertionError: Confirmed transaction terminal lost after queued UI callback: 2/2
	at com.example.ahakey.service.QueuedDeliveryChecks.main(QueuedDeliveryChecks.java:73)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
	at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:77)
	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
	at java.base/java.lang.reflect.Method.invoke(Method.java:569)
	at com.example.ahakey.wd010.CheckProcess.main(CheckProcess.java:7)

```

## 可复现fixture源码

下列源码只编译在临时目录，没有加入产品或仓库测试源码。保留全文避免临时目录清理后无法复核。编译和执行命令已在上方记录。显式退出/换号对照已由提交的47项覆盖；修复本队列时序时应增加同一FX阻塞窗口的退出/换号对照。

```java
package com.example.ahakey.service;

import com.example.ahakey.view.CloudAccountDialog;
import com.example.ahakey.platform.windows.WindowsCredentialStore;
import com.sun.net.httpserver.HttpServer;
import javafx.application.Platform;
import javafx.scene.control.*;
import javafx.stage.Stage;
import java.net.*;
import java.net.http.HttpClient;
import java.nio.file.*;
import java.time.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;

/** Independent R2 review fixture: real dialog callback queued before another request's 401. */
public final class QueuedDeliveryChecks {
    static CountDownLatch profileEntered,profileRelease,fxRelease;
    static final AtomicBoolean blockProfile=new AtomicBoolean(),expired=new AtomicBoolean();
    static CloudAccountDialog dialog;
    static <T>T fx(Callable<T> work)throws Exception{return CloudUiChecks.fx(work);}
    static Stage window(String title){return CloudUiChecks.window(title);}
    static Button button(Stage w,String title){return CloudUiChecks.button(w,title);}
    static ThreadPoolExecutor executor(Object owner,String name)throws Exception{
        var field=owner.getClass().getDeclaredField(name);field.setAccessible(true);return (ThreadPoolExecutor)field.get(owner);
    }
    public static void main(String[] args)throws Exception{
        CountDownLatch ready=new CountDownLatch(1);Platform.startup(ready::countDown);ready.await();Platform.setImplicitExit(false);
        var server=HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(),0),0);
        var network=Executors.newCachedThreadPool();server.setExecutor(network);
        server.createContext("/",x->{try{
            String path=x.getRequestURI().getPath();x.getRequestBody().readAllBytes();
            if(path.endsWith("/users/me")&&blockProfile.compareAndSet(true,false)){profileEntered.countDown();profileRelease.await();}
            String body=path.endsWith("/login")?"{\"code\":0,\"data\":{\"access_token\":\"fixture-token\"}}":
                path.endsWith("/redeem")?"{\"code\":0,\"data\":{}}":
                path.endsWith("/native")?"{\"code\":0,\"data\":{\"out_trade_no\":\"fixture-order\",\"code_url\":\"weixin://wxpay/bizpayurl?pr=fixture\"}}":
                path.endsWith("/order-status")?"{\"code\":0,\"data\":{\"status\":\"paid\"}}":
                expired.get()?"{\"code\":401}":"{\"code\":0,\"data\":{\"user\":{\"phone\":\"fixture\"},\"policy\":{\"recharge_prices_fen\":{\"monthly\":100}}}}";
            byte[] bytes=body.getBytes(java.nio.charset.StandardCharsets.UTF_8);x.sendResponseHeaders(200,bytes.length);x.getResponseBody().write(bytes);
        }catch(Exception ignored){}finally{x.close();}});server.start();
        var aha=new AhaTypeService(new AhaTypeConfig(Path.of(System.getProperty("user.home"),"account.json"),new WindowsCredentialStore()),HttpClient.newHttpClient(),URI.create("http://localhost:"+server.getAddress().getPort()),Clock.systemUTC());
        var account=new CloudAccountManager(aha,Duration.ofMillis(10),Duration.ofSeconds(5));
        int failures=0;
        try{
            for(boolean payment:new boolean[]{false,true}){
                expired.set(false);if(account.authenticate("fixture","fake",false,false)!=null)throw new AssertionError("fixture login failed");
                fx(()->{if(dialog!=null)dialog.close();dialog=new CloudAccountDialog(null,account,()->{});dialog.show();return null;});
                var origin=aha.session();profileEntered=new CountDownLatch(1);profileRelease=new CountDownLatch(1);blockProfile.set(true);
                if(payment){
                    var order=account.createOrder(new CloudAccountManager.Plan("monthly",100));
                    fx(()->{var method=CloudAccountDialog.class.getDeclaredMethod("showPayment",CloudAccountManager.Order.class,long.class);method.setAccessible(true);method.invoke(dialog,order,0L);return null;});
                }else fx(()->{button(window("云端账号 · AhaType"),"兑换码").fire();var w=window("兑换码");((TextField)w.getScene().getRoot().lookup(".text-field")).setText("fixture-coupon");button(w,"确认兑换").fire();return null;});
                if(!profileEntered.await(5,TimeUnit.SECONDS))throw new AssertionError("transaction did not reach profile read");
                CountDownLatch fxEntered=new CountDownLatch(1);fxRelease=new CountDownLatch(1);
                Platform.runLater(()->{fxEntered.countDown();try{fxRelease.await();}catch(InterruptedException e){Thread.currentThread().interrupt();}});
                if(!fxEntered.await(5,TimeUnit.SECONDS))throw new AssertionError("FX gate not entered");
                profileRelease.countDown();
                var worker=executor(payment?account:dialog,payment?"polling":"worker");long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);
                while(worker.getActiveCount()!=0&&System.nanoTime()<deadline)Thread.sleep(5);
                if(worker.getActiveCount()!=0||account.redeeming())throw new AssertionError("transaction completion not queued yet");
                expired.set(true);account.refreshProfile();
                if(account.isLoggedIn()||!aha.current(aha.operationDelivery(origin)))throw new AssertionError("expected server expiry without explicit logout/switch");
                fxRelease.countDown();
                String labels=fx(()->{var w=window(payment?"微信扫码支付":"兑换码");return w.getScene().getRoot().lookupAll(".label").stream().map(n->((Label)n).getText()).reduce("",(a,b)->a+" | "+b);});
                boolean terminal=labels.contains(payment?"支付成功":"兑换成功");
                System.out.println((payment?"payment":"coupon")+" success callback was queued; server expiry mapping valid; terminalShown="+terminal+"; labels="+labels);
                if(!terminal)failures++;
            }
        }finally{
            if(profileRelease!=null)profileRelease.countDown();if(fxRelease!=null)fxRelease.countDown();
            fx(()->{if(dialog!=null)dialog.close();return null;});account.close();server.stop(0);network.shutdownNow();Platform.exit();
        }
        if(failures!=0)throw new AssertionError("Confirmed transaction terminal lost after queued UI callback: "+failures+"/2");
        System.out.println("PASS QueuedDeliveryChecks");
    }
}

```
