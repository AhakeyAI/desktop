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
import java.util.concurrent.atomic.*;
import java.util.*;
import java.util.function.Consumer;

/** R2 review reproduction plus queued logout, account/window generation and terminal text checks. */
public final class QueuedDeliveryChecks {
    static CountDownLatch profileEntered,profileRelease,fxRelease;
    static final AtomicBoolean blockProfile=new AtomicBoolean(),expired=new AtomicBoolean();
    static CloudAccountDialog dialog;
    static int checks;
    static void check(boolean value,String message){checks++;if(!value)throw new AssertionError(message);}
    static String labels(Stage w){return w.getScene().getRoot().lookupAll(".label").stream().map(n->((Label)n).getText()).reduce("",(a,b)->a+" | "+b);}
    static long paymentTicket()throws Exception{var f=CloudAccountDialog.class.getDeclaredField("paymentWindow");f.setAccessible(true);return f.getLong(dialog);}
    static long pollGeneration(CloudAccountManager account)throws Exception{var f=CloudAccountManager.class.getDeclaredField("pollGeneration");f.setAccessible(true);return ((AtomicLong)f.get(account)).get();}
    static void complete(CloudAccountManager account,long generation,CloudAccountManager.OperationResult result,Consumer<CloudAccountManager.OperationResult> callback)throws Exception{
        var m=CloudAccountManager.class.getDeclaredMethod("complete",long.class,Consumer.class,CloudAccountManager.OperationResult.class);m.setAccessible(true);m.invoke(account,generation,callback,result);
    }
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
        try{
            for(boolean payment:new boolean[]{false,true}){
                var scenarios=new ArrayList<>(List.of("server_expiry","logout","switch_account","close_dialog"));
                scenarios.add(payment?"close_payment":"hide_reopen_coupon");
                if(payment)scenarios.add("close_reopen_payment");
                for(String scenario:scenarios){
                    expired.set(false);check(account.authenticate("fixture","fake",false,false)==null,"fixture login succeeds");
                    AtomicInteger delivered=new AtomicInteger();
                    fx(()->{if(dialog!=null)dialog.close();dialog=new CloudAccountDialog(null,account,delivered::incrementAndGet);dialog.show();return null;});
                    var origin=aha.session();profileEntered=new CountDownLatch(1);profileRelease=new CountDownLatch(1);blockProfile.set(true);
                    if(payment){
                        var order=account.createOrder(new CloudAccountManager.Plan("monthly",100));
                        fx(()->{var method=CloudAccountDialog.class.getDeclaredMethod("showPayment",CloudAccountManager.Order.class,long.class);method.setAccessible(true);method.invoke(dialog,order,paymentTicket());return null;});
                    }else fx(()->{button(window("云端账号 · AhaType"),"兑换码").fire();var w=window("兑换码");((TextField)w.getScene().getRoot().lookup(".text-field")).setText("fixture-coupon");button(w,"确认兑换").fire();return null;});
                    check(profileEntered.await(5,TimeUnit.SECONDS),"transaction reached profile read");
                    Stage transaction=fx(()->window(payment?"微信扫码支付":"兑换码"));
                    CountDownLatch fxEntered=new CountDownLatch(1);fxRelease=new CountDownLatch(1);
                    Platform.runLater(()->{
                        fxEntered.countDown();try{fxRelease.await();}catch(InterruptedException e){Thread.currentThread().interrupt();}
                        // Runs on FX after result was queued, but before that result can be consumed.
                        if(scenario.equals("close_dialog")){dialog.close();dialog=new CloudAccountDialog(null,account,delivered::incrementAndGet);dialog.show();}
                        else if(scenario.equals("close_payment"))transaction.close();
                        else if(scenario.equals("close_reopen_payment")){transaction.close();transaction.show();}
                        else if(scenario.equals("hide_reopen_coupon")){transaction.hide();button(window("云端账号 · AhaType"),"兑换码").fire();}
                    });
                    check(fxEntered.await(5,TimeUnit.SECONDS),"FX gate entered");
                    profileRelease.countDown();
                    var worker=executor(payment?account:dialog,payment?"polling":"worker");long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(5);
                    while(worker.getActiveCount()!=0&&System.nanoTime()<deadline)Thread.sleep(5);
                    check(worker.getActiveCount()==0&&!account.redeeming(),"successful result queued after profile200");
                    if(scenario.equals("server_expiry")){
                        expired.set(true);account.refreshProfile();check(!account.isLoggedIn()&&aha.current(aha.operationDelivery(origin)),"same-origin server expiry remains deliverable");
                    }else if(scenario.equals("logout")||scenario.equals("switch_account")){
                        account.logout();if(scenario.equals("switch_account"))check(account.authenticate("replacement","fake",false,false)==null,"replacement authenticated");
                    }
                    fxRelease.countDown();
                    fx(()->{
                        String text=labels(transaction);boolean expected=scenario.equals("server_expiry")||scenario.equals("hide_reopen_coupon");
                        check(text.contains(payment?"支付成功":"兑换成功")==expected,scenario+" confirmed terminal visibility");
                        check(delivered.get()==(expected?1:0),scenario+" does not deliver stale or duplicate callbacks");
                        if(scenario.equals("server_expiry")){
                            check(text.contains("请重新登录")&&!text.contains("账号信息已刷新"),"current expiry replaces stale refreshed claim");
                            check(!text.contains("正在兑换")&&!text.contains("正在查询付款"),"terminal exits in-progress state");
                            check(button(window("云端账号 · AhaType"),"登录")!=null,"main window returns to login");
                        }
                        if(scenario.equals("hide_reopen_coupon"))check(window("兑换码")==transaction,"same coupon operation retained on reopen");
                        if(scenario.equals("close_reopen_payment"))transaction.close();
                        return null;
                    });
                    if(scenario.equals("switch_account"))check(account.isLoggedIn(),"old callback preserves replacement account");
                    System.out.println((payment?"payment":"coupon")+" queued result scenario="+scenario+" PASS");
                }
            }
            // Service completion uses the same late-resolution rule before handing results to FX.
            expired.set(false);check(account.authenticate("fixture","fake",false,false)==null,"service boundary login");
            var original=aha.session();long generation=pollGeneration(account);
            var pending=new CloudAccountManager.OperationResult("支付成功，账号信息已刷新",original,true,false);
            expired.set(true);account.refreshProfile();AtomicReference<CloudAccountManager.OperationResult> received=new AtomicReference<>();
            complete(account,generation,pending,received::set);
            check(received.get()!=null&&received.get().message().contains("请重新登录")&&!received.get().message().contains("账号信息已刷新"),"service final completion re-resolves expiry and message");
            received.set(null);account.cancelPaymentPolling();complete(account,generation,pending,received::set);check(received.get()==null,"cancelled polling generation cannot complete");
            generation=pollGeneration(account);account.logout();complete(account,generation,pending,received::set);check(received.get()==null,"explicit logout cannot complete old operation");
            expired.set(false);account.authenticate("replacement","fake",false,false);complete(account,pollGeneration(account),pending,received::set);check(received.get()==null,"new authentication cannot complete old operation");
        }finally{
            if(profileRelease!=null)profileRelease.countDown();if(fxRelease!=null)fxRelease.countDown();
            fx(()->{if(dialog!=null)dialog.close();return null;});account.close();server.stop(0);network.shutdownNow();Platform.exit();
        }
        System.out.println("PASS QueuedDeliveryChecks "+checks+" checks; real queued FX transaction callbacks, loopback only");
    }
}
