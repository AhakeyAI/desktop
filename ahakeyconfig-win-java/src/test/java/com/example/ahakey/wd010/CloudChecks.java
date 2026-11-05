package com.example.ahakey.service;

import com.example.ahakey.platform.windows.WindowsCredentialStore;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import java.io.*;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Loopback-only HTTP plus real DPAPI on synthetic credentials; never uses the user's account. */
public final class CloudChecks {
    private static int checks;
    static void check(boolean value,String label){checks++;if(!value)throw new AssertionError(label);}
    interface Checked{void run()throws Exception;}
    static void fails(Checked action,String label)throws Exception{try{action.run();throw new AssertionError(label);}catch(IOException|IllegalArgumentException expected){checks++;}}
    public static void main(String[] args)throws Exception{
        Path root=Files.createTempDirectory("wd010-cloud-");
        credentials(root);
        HttpServer server=HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(),0),0);
        ExecutorService network=Executors.newCachedThreadPool(r->{Thread t=new Thread(r);t.setDaemon(true);return t;});server.setExecutor(network);
        AtomicReference<String> process=new AtomicReference<>("{\"code\":0,\"data\":{\"text\":\"整理后的文本\"}}");
        AtomicReference<String> profile=new AtomicReference<>("{\"code\":200,\"data\":{\"user\":{\"phone\":\"fixture\"},\"quota\":{\"used_daily\":1,\"limit_daily\":20},\"policy\":{\"recharge_prices_fen\":{\"monthly\":100},\"enable_monthly\":false}}}");
        AtomicReference<CountDownLatch> loginEntered=new AtomicReference<>(),loginRelease=new AtomicReference<>();
        AtomicReference<CountDownLatch> processEntered=new AtomicReference<>(),processRelease=new AtomicReference<>();
        AtomicBoolean failProfile=new AtomicBoolean(),rejectRedeem=new AtomicBoolean(),delayProcess=new AtomicBoolean();
        AtomicInteger requests=new AtomicInteger(),orders=new AtomicInteger(),redeems=new AtomicInteger(),polls=new AtomicInteger();
        AtomicReference<String> paymentState=new AtomicReference<>("mystery");
        AtomicReference<String> orderBody=new AtomicReference<>("{\"code\":0,\"data\":{\"out_trade_no\":\"fixture-order\",\"code_url\":\"weixin://wxpay/bizpayurl?pr=fixture\"}}");
        server.createContext("/",exchange->{
            String path=exchange.getRequestURI().getPath();String body="{\"code\":0,\"data\":{}}";int code=200;
            try{
                exchange.getRequestBody().readAllBytes();
                if(path.endsWith("/login")){if(loginEntered.get()!=null){loginEntered.get().countDown();loginRelease.get().await();}body="{\"code\":0,\"data\":{\"access_token\":\"synthetic-session\"}}";}
                else if(path.endsWith("/users/me")){if(failProfile.get()){code=503;body="{}";}else body=profile.get();}
                else if(path.endsWith("/process")){requests.incrementAndGet();if(processEntered.get()!=null){processEntered.get().countDown();processRelease.get().await();}if(delayProcess.get())Thread.sleep(22000);body=process.get();}
                else if(path.endsWith("/redeem")){redeems.incrementAndGet();if(rejectRedeem.get())body="{\"code\":400,\"msg\":\"already used\"}";}
                else if(path.endsWith("/native")){orders.incrementAndGet();body=orderBody.get();}
                else if(path.endsWith("/order-status")){polls.incrementAndGet();body="{\"code\":0,\"data\":{\"status\":\""+paymentState.get()+"\"}}";}
                byte[] bytes=body.getBytes(java.nio.charset.StandardCharsets.UTF_8);exchange.sendResponseHeaders(code,bytes.length);exchange.getResponseBody().write(bytes);
            }catch(Exception ignored){}finally{exchange.close();}
        });server.start();
        URI base=URI.create("http://localhost:"+server.getAddress().getPort());
        AhaTypeService aha=new AhaTypeService(new AhaTypeConfig(root.resolve("account.json"),new WindowsCredentialStore()),HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).build(),base,Clock.systemUTC());
        CloudAccountManager account=new CloudAccountManager(aha,Duration.ofMillis(10),Duration.ofMillis(180));
        ExecutorService workers=Executors.newCachedThreadPool();
        try{
            check(!aha.isRememberPassword()&&!aha.isEnabled(),"defaults do not remember or fake enabled");
            check(account.authenticate("fixture","fake-password",false,true).contains("注册成功，请登录")&&!account.isLoggedIn(),"registration without token");
            check(account.authenticate("fixture","fake-password",true,false)==null&&account.isLoggedIn(),"login and actual profile refresh");
            check(aha.getQuota().size()==2&&!aha.getQuota().containsKey("limit_monthly"),"missing quota stays unknown");
            aha.setEnabled(true);check(aha.process("原文").text().equals("整理后的文本"),"real process endpoint and output");
            process.set("{\"code\":0,\"data\":{\"text\":\"\"}}");check(aha.process("原文").text().equals("原文"),"empty response fallback");
            process.set("{\"code\":0.5,\"data\":{\"text\":\"must reject\"}}");check(aha.process("原文").text().equals("原文"),"fractional business code rejected");
            process.set("{\"code\":\"200\",\"data\":{\"result\":\"历史兼容\"}}");check(aha.process("原文").text().equals("历史兼容"),"historical string business code accepted");
            process.set("invalid-json");check(aha.process("原文").text().equals("原文"),"malformed response fallback");
            process.set("{\"code\":0,\"data\":{\"result\":\"整理\"}}");aha.setEnabled(false);int calls=requests.get();check(aha.process("原文").text().equals("原文")&&requests.get()==calls,"toggle skips requests");aha.setEnabled(true);
            profile.set("{\"code\":0,\"data\":{\"token_valid_until\":\"2000-01-01T00:00:00Z\"}}");account.refreshProfile();check(aha.getStatusMessage().contains("服务已到期")&&account.isLoggedIn(),"known expired entitlement is shown without logging out");check(aha.process("原文").message().contains("服务已到期")&&account.isLoggedIn(),"entitlement expiry is not session expiry");
            profile.set("{\"code\":\"0\",\"data\":{\"quota\":{\"token_valid_until\":946684800}}}");account.refreshProfile();check(aha.getTokenValidUntil().equals("946684800")&&aha.process("原文").message().contains("服务已到期"),"historical quota numeric expiry");
            profile.set("{\"code\":0,\"data\":{\"token_valid_until\":\"2099-01-01T00:00:00Z\",\"quota\":{\"used_daily\":20,\"limit_daily\":20}}}");account.refreshProfile();check(aha.getStatusMessage().contains("额度不足"),"known exhausted quota is shown after refresh");check(aha.process("原文").message().contains("额度不足")&&aha.getStatusMessage().contains("已使用原文"),"quota fallback updates actual status");
            profile.set("{\"code\":0,\"data\":{\"token_valid_until\":\"2099-01-01T00:00:00Z\",\"quota\":{\"used_daily\":1,\"limit_daily\":20},\"policy\":{\"recharge_prices_fen\":{\"monthly\":100}}}}");account.refreshProfile();
            profile.set("{\"code\":0,\"data\":{\"quota\":{\"usedDaily\":\"1\",\"limitDaily\":\"20\"},\"policy\":{\"enableMonthly\":\"0\",\"rechargePricesFen\":{\"monthly\":\"100\",\"quarterly\":\"250\",\"yearly\":\"900\"}}}}");account.refreshProfile();check(aha.getQuota().get("used_daily").equals(1L)&&Boolean.FALSE.equals(aha.getPolicy().get("enable_monthly"))&&account.plans().size()==3,"historical numeric strings and camelCase policy remain valid");
            failProfile.set(true);check(account.refreshProfile()!=null&&account.isLoggedIn()&&aha.getQuota().get("used_daily").equals(1L),"refresh failure retains account and old data");
            check(account.redeem("synthetic-code").contains("兑换成功，但账号信息刷新失败")&&redeems.get()==1,"redemption success separated from refresh failure");
            rejectRedeem.set(true);check(!account.redeem("synthetic-code").contains("兑换成功")&&redeems.get()==2,"used/rejected coupon not success");failProfile.set(false);
            var order=account.createOrder(account.plans().get(0));check(order.amountFen()==100&&order.quotedAmount()&&orders.get()==1,"legacy missing amount uses labelled quote");
            CompletableFuture<String> pollResult=new CompletableFuture<>();account.startPaymentPolling(order,pollResult::complete);check(pollResult.get(5,TimeUnit.SECONDS).contains("未确认"),"unknown payment state never successful");
            paymentState.set("success");failProfile.set(true);pollResult=new CompletableFuture<>();account.startPaymentPolling(order,pollResult::complete);check(pollResult.get(5,TimeUnit.SECONDS).contains("支付成功，但账号信息刷新失败"),"paid is separate from entitlement refresh");failProfile.set(false);
            CountDownLatch noCompletion=new CountDownLatch(1);account.startPaymentPolling(order,s->noCompletion.countDown());account.cancelPaymentPolling();Thread.sleep(60);check(noCompletion.getCount()==1,"window cancellation suppresses polling completion");
            orderBody.set("{\"code\":0,\"data\":{\"out_trade_no\":\"fixture\",\"code_url\":\"javascript:bad\"}}");try{account.createOrder(account.plans().get(0));throw new AssertionError("bad URL");}catch(IllegalStateException expected){checks++;}check(orders.get()==2,"invalid order never retried");
            processEntered.set(new CountDownLatch(1));processRelease.set(new CountDownLatch(1));Future<AhaTypeService.ProcessResult> late=workers.submit(()->aha.process("原文"));check(processEntered.get().await(3,TimeUnit.SECONDS),"process entered");check(aha.getStatusMessage().contains("正在整理"),"processing status reflects current request");account.logout();processRelease.get().countDown();check(late.get().text().equals("原文")&&!account.isLoggedIn(),"late process cannot resurrect account or return old optimized text");check(aha.getStatusMessage().equals("未登录"),"late fallback cannot overwrite logout status");processEntered.set(null);
            check(aha.isRememberPassword()&&aha.getRememberedPassword().equals("fake-password"),"logout retains opt-in fill only");aha.remember("fixture","",false);check(!aha.isRememberPassword()&&aha.getRememberedPassword().isEmpty(),"uncheck removes saved password");
            var clicked=aha.session();long nextGeneration=aha.beginAuthentication();aha.authenticate(nextGeneration,"next-account","other","",false);int oldRedeems=redeems.get(),oldOrders=orders.get();check(account.redeem("synthetic-code",clicked).contains("账号已变化")&&redeems.get()==oldRedeems,"queued redemption cannot switch to execution-time account");
            try{account.createOrder(new CloudAccountManager.Plan("monthly",100),clicked);throw new AssertionError("old account order");}catch(IllegalStateException expected){checks++;}check(orders.get()==oldOrders,"queued order emits zero writes on account change");
            loginEntered.set(new CountDownLatch(1));loginRelease.set(new CountDownLatch(1));Future<String> lateLogin=workers.submit(()->account.authenticate("fixture","fake-password",false,false));check(loginEntered.get().await(3,TimeUnit.SECONDS),"login entered");account.logout();loginRelease.get().countDown();lateLogin.get();check(!account.isLoggedIn(),"late login cannot undo logout");loginEntered.set(null);
            account.authenticate("fixture","fake-password",false,false);delayProcess.set(true);long before=System.nanoTime();var timeout=aha.process("超时原文");long seconds=TimeUnit.NANOSECONDS.toSeconds(System.nanoTime()-before);check(timeout.text().equals("超时原文")&&timeout.message().contains("超时")&&seconds>=19&&seconds<22,"actual HTTP 20 second timeout falls back once");delayProcess.set(false);
            process.set("{\"code\":500,\"data\":402}");check(aha.process("原文").text().equals("原文")&&account.isLoggedIn(),"generic business 500 does not invalidate session");
            process.set("{\"code\":500,\"data\":401}");check(aha.process("原文").text().equals("原文")&&!account.isLoggedIn(),"historical HTTP200 invalid session clears session");
        }finally{account.close();workers.shutdownNow();server.stop(0);network.shutdownNow();}
        System.out.println("PASS CloudChecks "+checks+" checks; loopback HTTP, synthetic credentials, no real account/payment/coupon");
    }
    private static void credentials(Path root)throws Exception{
        Path path=root.resolve("legacy.json");String legacy="{\"remember_password\":true,\"remembered_password\":\"synthetic-secret\",\"access_token\":\"synthetic-token\",\"unrelated\":42}";Files.writeString(path,legacy);
        AhaTypeConfig config=new AhaTypeConfig(path,new WindowsCredentialStore());var data=config.load();check(data.get("unrelated").equals(42)&&data.get("remembered_password").equals("synthetic-secret"),"DPAPI migration retains fields");
        check(!Files.readString(path).contains("synthetic-secret")&&!Files.readString(path).contains("synthetic-token"),"encrypted disk has no plaintext credential");check(config.load().equals(data),"DPAPI roundtrip");
        Path failure=root.resolve("migration-fail.json");Files.writeString(failure,legacy);AhaTypeConfig bad=new AhaTypeConfig(failure,new WindowsCredentialStore(){@Override public byte[] protect(byte[] plain)throws IOException{throw new IOException("fixture");}});
        fails(bad::load,"protection failure surfaced");check(Files.readString(failure).equals(legacy),"failed migration leaves original bytes intact");
        for(String corrupt:List.of("null","[]","{\"schema\":1,\"protected_state\":null}","{\"schema\":1,\"protected_state\":\"bad-base64!\"}")){
            Path p=root.resolve("bad-"+checks+".json");Files.writeString(p,corrupt);fails(()->new AhaTypeConfig(p,new WindowsCredentialStore()).load(),"corrupt envelope rejected");
            var service=new AhaTypeService(new AhaTypeConfig(p,new WindowsCredentialStore()),HttpClient.newHttpClient(),URI.create("http://localhost"),Clock.systemUTC());check(!service.hasValidToken()&&service.getStatusMessage().contains("失败"),"corrupt config does not crash startup");
        }
    }
}
