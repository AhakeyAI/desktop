package com.example.ahakey.service;

import com.fasterxml.jackson.databind.JsonNode;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import java.util.function.Consumer;

/** Cloud commands have no automatic write retries. Query polling belongs to one account/window. */
public final class CloudAccountManager implements AutoCloseable {
    private static class Holder { static final CloudAccountManager INSTANCE=new CloudAccountManager(AhaTypeService.getInstance()); }
    public static CloudAccountManager getInstance(){return Holder.INSTANCE;}
    private final AhaTypeService aha;
    private final AtomicBoolean authenticating=new AtomicBoolean();
    private final AtomicBoolean redeeming=new AtomicBoolean();
    private final AtomicBoolean ordering=new AtomicBoolean();
    private final AtomicLong pollGeneration=new AtomicLong();
    private final ExecutorService polling=Executors.newCachedThreadPool(r->{Thread t=new Thread(r,"account-query");t.setDaemon(true);return t;});
    private final Duration pollInterval,pollTimeout;
    private volatile String status="未登录";
    private volatile String redeemStatus="";
    private volatile boolean closed;
    public CloudAccountManager(AhaTypeService aha){this(aha,Duration.ofSeconds(2),Duration.ofMinutes(3));}
    public CloudAccountManager(AhaTypeService aha,Duration interval,Duration timeout){this.aha=aha;pollInterval=interval;pollTimeout=timeout;status=aha.getStatusMessage();}
    public AhaTypeService ahaType(){return aha;}
    public String status(){return status;}
    public String redeemStatus(){return redeemStatus;}
    public boolean redeeming(){return redeeming.get();}
    public boolean isLoggedIn(){return aha.hasValidToken();}
    public String accountName(){return AhaTypeService.string(aha.getUserProfile().getOrDefault("phone","未获取"));}
    public String authenticate(String phone,String password,boolean remember,boolean register){
        if(closed)return "账号服务已停止";
        if(phone==null||phone.isBlank()||password==null||password.isEmpty())return "请输入手机号和密码";
        if(!authenticating.compareAndSet(false,true))return "账号请求进行中";
        cancelPaymentPolling();long g=aha.beginAuthentication();
        try{
            JsonNode root=aha.request("/api/v1/auth/"+(register?"register":"login"),"POST",Map.of("phone",phone.trim(),"password",password),null);
            if(closed||!aha.generationCurrent(g))return "账号已变化，忽略旧请求";
            JsonNode data=AhaTypeService.data(root);
            String token=AhaTypeService.firstText(data,"access_token","token");
            if(token.isBlank())token=AhaTypeService.firstText(root,"access_token","token");
            if(token.isBlank())return status=register?"注册成功，请登录":"登录响应未提供有效会话";
            if(!aha.authenticate(g,token,phone.trim(),password,remember))return "账号已变化，忽略旧请求";
            String refresh=refreshProfile();
            return refresh==null?null:"登录成功，但账号信息未刷新："+refresh;
        }catch(Exception e){
            if(!aha.generationCurrent(g))return "账号已变化，忽略旧请求";
            return status=e instanceof AhaTypeService.CloudFailure?e.getMessage():register?"注册结果未确认，可尝试登录；未自动重复注册":"登录请求或本地保存失败，请检查网络和存储后重试";
        }finally{authenticating.set(false);}
    }
    public record OperationResult(String message,AhaTypeService.Session delivery,boolean success,boolean unknown){}
    /** Revalidate at consumption time, including after an asynchronous UI queue boundary. */
    public void deliverOperation(OperationResult result,Consumer<OperationResult> completion){
        synchronized(aha){
            var delivery=aha.operationDelivery(result.delivery());
            if(!aha.current(delivery))return;
            String message=result.message();
            if(result.success()&&delivery.token().isBlank())
                message=(message.startsWith("支付成功")?"支付成功":"兑换成功")+"；登录已失效，请重新登录";
            completion.accept(new OperationResult(message,delivery,result.success(),result.unknown()));
        }
    }
    private record RefreshResult(String error,AhaTypeService.Session delivery){}
    public String refreshProfile(){return refreshProfile(aha.session());}
    public String refreshProfile(AhaTypeService.Session s){return refreshForOperation(s).error();}
    private RefreshResult refreshForOperation(AhaTypeService.Session s){
        if(!aha.current(s)){var delivery=aha.operationDelivery(s);return new RefreshResult(aha.current(delivery)?"登录已失效，请重新登录":"账号已变化，忽略旧刷新",delivery);}
        if(s.token().isBlank())return new RefreshResult("未登录，请先登录",s);
        try{
            JsonNode data=AhaTypeService.data(aha.request("/api/v1/auth/users/me","GET",null,s));
            synchronized(aha){if(!aha.update(s,data))return new RefreshResult("账号已变化或登录失效，资料未刷新",aha.operationDelivery(s));status="账号信息已刷新";}
            return new RefreshResult(null,s);
        }catch(Exception e){
            var delivery=e instanceof AhaTypeService.CloudFailure f&&f.fallbackSession!=null?f.fallbackSession:aha.operationDelivery(s);
            synchronized(aha){if(aha.current(delivery))status=delivery.token().isBlank()?"登录已失效，请重新登录":"账号信息未刷新，保留上次数据";}
            return new RefreshResult(e instanceof AhaTypeService.CloudFailure?e.getMessage():"网络或本地保存失败，数据未刷新",delivery);
        }
    }
    public String logout(){
        synchronized(aha){
        cancelPaymentPolling();redeemStatus="";
        try{aha.logout();status="已退出登录";return null;}
        catch(Exception e){return status="当前会话已停用，但本地退出保存失败；请检查存储后再次退出";}
        }
    }
    public String redeem(String code){return redeem(code,aha.session());}
    public String redeem(String code,AhaTypeService.Session s){return redeemResult(code,s).message();}
    public OperationResult redeemResult(String code,AhaTypeService.Session s){
        if(code==null||code.isBlank())return new OperationResult("请输入兑换码",s,false,false);
        synchronized(aha){
            if(!aha.current(s))return new OperationResult("账号已变化，请重新确认兑换账号",s,false,false);
            if(s.token().isBlank())return new OperationResult("请先登录",s,false,false);
            if(!redeeming.compareAndSet(false,true))return new OperationResult("兑换正在进行，请勿重复提交",s,false,false);
            redeemStatus="正在兑换…";
        }
        try{
            aha.request("/api/v1/coupon/redeem","POST",Map.of("code",code.trim()),s);
            if(!aha.current(aha.operationDelivery(s)))return new OperationResult("账号已变化；旧兑换结果不应用到当前账号",s,true,false);
            var refresh=refreshForOperation(s);
            String message=refresh.error()==null?"兑换成功":"兑换成功，但账号信息刷新失败；"+(refresh.delivery().token().isBlank()?"请重新登录":"请刷新账号");
            var result=new OperationResult(message,refresh.delivery(),true,false);
            deliverOperation(result,current->redeemStatus=current.message());
            return result;
        }catch(Exception e){
            boolean unknown=!(e instanceof AhaTypeService.CloudFailure);
            String message=unknown?"兑换结果未确认；未自动重发，请刷新账号核对":"兑换未成功："+e.getMessage();
            var delivery=e instanceof AhaTypeService.CloudFailure f&&f.fallbackSession!=null?f.fallbackSession:aha.operationDelivery(s);
            synchronized(aha){if(aha.current(delivery))redeemStatus=message;}
            return new OperationResult(message,delivery,false,unknown);
        }finally{redeeming.set(false);}
    }
    public record Plan(String id,int amountFen){
        @Override public String toString(){return (switch(id){case "monthly"->"包月";case "quarterly"->"包季";default->"包年";})+String.format(Locale.ROOT," %.2f 元",amountFen/100.0);}
    }
    public record Order(String number,String url,int amountFen,boolean quotedAmount,AhaTypeService.Session session){}
    public List<Plan> plans(){
        Map<String,Object> prices=AhaTypeService.map(aha.getPolicy().get("recharge_prices_fen"));var result=new ArrayList<Plan>();
        for(String id:List.of("monthly","quarterly","yearly")){Long amount=AhaTypeService.integer(prices.get(id));if(amount!=null&&amount>0&&amount<=Integer.MAX_VALUE)result.add(new Plan(id,amount.intValue()));}
        return List.copyOf(result);
    }
    public Order createOrder(Plan selected) throws Exception {
        return createOrder(selected,aha.session());
    }
    public Order createOrder(Plan selected,AhaTypeService.Session s) throws Exception {
        if(!aha.current(s))throw new IllegalStateException("账号已变化，请重新选择套餐并确认");
        if(!plans().contains(selected))throw new IllegalArgumentException("套餐报价已变化，请重新选择");
        if(s.token().isBlank())throw new IllegalStateException("请先登录");
        if(!ordering.compareAndSet(false,true))throw new IllegalStateException("正在创建订单，请勿重复提交");
        try{
            JsonNode d=AhaTypeService.data(aha.request("/api/v1/payment/wechat/native","POST",Map.of("plan",selected.id()),s));
            if(!aha.current(s))throw new IllegalStateException("账号已变化，旧订单不显示");
            String number=AhaTypeService.firstText(d,"out_trade_no","outTradeNo");
            String url=AhaTypeService.firstText(d,"code_url","codeUrl","h5_url","h5Url","mweb_url","mwebUrl");
            URI uri=URI.create(url);
            boolean valid="weixin".equalsIgnoreCase(uri.getScheme())&&"wxpay".equalsIgnoreCase(uri.getHost()) || "https".equalsIgnoreCase(uri.getScheme())&&uri.getHost()!=null&&uri.getUserInfo()==null;
            if(number.isBlank()||!valid)throw new IllegalStateException("订单号或支付链接无效，未显示付款二维码");
            JsonNode amount=AhaTypeService.alias(d,"amount_fen");
            Long parsed=amount==null?null:AhaTypeService.integer(amount.asText());
            if(amount!=null&&(parsed==null||parsed<=0||parsed>Integer.MAX_VALUE))throw new IllegalStateException("订单金额无效");
            return new Order(number,url,amount==null?selected.amountFen():parsed.intValue(),amount==null,s);
        }finally{ordering.set(false);}
    }
    public void startPaymentPolling(Order order,Consumer<String> completion){startPaymentPollingResult(order,result->completion.accept(result.message()));}
    public void startPaymentPollingResult(Order order,Consumer<OperationResult> completion){
        long g=pollGeneration.incrementAndGet();
        polling.execute(()->{
            long deadline=System.nanoTime()+pollTimeout.toNanos();
            while(currentPoll(g,order)&&System.nanoTime()<deadline){
                try{
                    TimeUnit.NANOSECONDS.sleep(pollInterval.toNanos());if(!currentPoll(g,order))return;
                    JsonNode d=AhaTypeService.data(aha.request("/api/v1/payment/wechat/order-status?outTradeNo="+URLEncoder.encode(order.number(),StandardCharsets.UTF_8),"GET",null,order.session()));
                    if(g!=pollGeneration.get()||!aha.current(aha.operationDelivery(order.session())))return;
                    String state=AhaTypeService.firstText(d,"status","tradeState","trade_state","payStatus","pay_status","orderStatus","order_status").toLowerCase(Locale.ROOT).replace('-','_');
                    // Exact historical client state mapping; unknown values remain unconfirmed.
                    if(List.of("paid","success","succeeded","complete","completed","pay_success","trade_success","wechat_success","finished","done","1").contains(state)){
                        var refresh=refreshForOperation(order.session());
                        String message=refresh.error()==null?"支付成功，账号信息已刷新":"支付成功，但账号信息刷新失败；"+(refresh.delivery().token().isBlank()?"请重新登录":"请刷新账号");
                        complete(g,completion,new OperationResult(message,refresh.delivery(),true,false));return;
                    }
                    if(List.of("failed","failure","fail","closed","cancelled","canceled","expired","timeout","trade_closed","pay_error","2").contains(state)){
                        complete(g,order,completion,"服务端报告订单未完成："+state);return;
                    }
                }catch(InterruptedException e){Thread.currentThread().interrupt();return;}
                catch(Exception e){complete(g,order,completion,"查询异常，支付结果未确认；关闭窗口不会取消后端订单");return;}
            }
            complete(g,order,completion,"查询期限已到，支付结果未确认；请勿据此重复付款");
        });
    }
    private boolean currentPoll(long g,Order order){return g==pollGeneration.get()&&aha.current(order.session());}
    private void complete(long g,Order o,Consumer<OperationResult> c,String message){complete(g,c,new OperationResult(message,aha.operationDelivery(o.session()),false,message.contains("未确认")));}
    private void complete(long g,Consumer<OperationResult> c,OperationResult result){deliverOperation(result,current->{if(g==pollGeneration.get())c.accept(current);});}
    public void cancelPaymentPolling(){pollGeneration.incrementAndGet();}
    @Override public void close(){closed=true;aha.invalidatePendingOperations();cancelPaymentPolling();polling.shutdownNow();}
}
