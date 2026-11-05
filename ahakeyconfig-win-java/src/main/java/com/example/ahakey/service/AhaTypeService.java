package com.example.ahakey.service;

import com.fasterxml.jackson.databind.*;
import java.io.IOException;
import java.net.URI;
import java.net.http.*;
import java.time.*;
import java.util.*;

/** Account generation is the authority for every cloud completion, including speech final. */
public class AhaTypeService {
    public static final Duration REQUEST_TIMEOUT = Duration.ofSeconds(20);
    public static final String DEFAULT_API_BASE = "https://956798.xyz/prod-api";
    private static class Holder { static final AhaTypeService INSTANCE = new AhaTypeService(); }
    private final AhaTypeConfig config;
    private final HttpClient http;
    private final URI base;
    private final Clock clock;
    private final ObjectMapper json = new ObjectMapper();
    private Map<String,Object> values = new LinkedHashMap<>();
    private long generation;
    private Session serverExpiredOrigin,serverExpiredDelivery;
    private String status = "AhaType 未启用";
    private boolean storageReady;
    public record Session(long generation, String token) {}
    public record ProcessResult(String text, String message, java.util.function.BooleanSupplier stillCurrent) {
        public ProcessResult(String text,String message){this(text,message,()->true);}
        public boolean deliverable(){return stillCurrent.getAsBoolean();}
    }
    public static AhaTypeService getInstance() { return Holder.INSTANCE; }
    public AhaTypeService() { this(new AhaTypeConfig(), HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).build(), configuredApiBase(), Clock.systemUTC()); }
    public AhaTypeService(AhaTypeConfig config, HttpClient http, URI base, Clock clock) {
        this.config=config;this.http=http;this.base=base;this.clock=clock;
        try { values=config.load(); storageReady=true; status=readyStatus(); }
        catch (IOException e) { status="账号安全存储读取/迁移失败；未加载凭据，请检查存储权限"; }
    }
    public static URI configuredApiBase() {
        String value=System.getenv("VIBE_TYPELESS_API_BASE");
        if(value==null||value.isBlank()) value=System.getenv("VIBE_API_BASE");
        return URI.create(value==null||value.isBlank()?DEFAULT_API_BASE:value);
    }
    public synchronized Session session() { return new Session(generation, string(values.get("access_token"))); }
    public synchronized boolean current(Session s) { return s.generation()==generation && s.token().equals(string(values.get("access_token"))); }
    public synchronized long beginAuthentication() { serverExpiredOrigin=null;serverExpiredDelivery=null;return ++generation; }
    public synchronized void invalidatePendingOperations(){serverExpiredOrigin=null;serverExpiredDelivery=null;generation++;}
    public synchronized boolean generationCurrent(long g) { return g==generation; }
    public synchronized boolean isEnabled() { return Boolean.TRUE.equals(values.get("typeless_enabled")); }
    public synchronized String getStatusMessage() { return status; }
    public synchronized boolean hasValidToken() {
        String token=session().token();if(token.isBlank())return false;
        String[] parts=token.split("\\.",-1);
        if(parts.length==3)try{JsonNode payload=json.readTree(Base64.getUrlDecoder().decode(parts[1]));JsonNode expiry=payload.get("exp");if(expiry!=null&&expiry.isIntegralNumber())return Instant.ofEpochSecond(expiry.longValue()).isAfter(clock.instant());}catch(Exception ignored){}
        return true;
    }
    public synchronized boolean isRememberPassword() { return Boolean.TRUE.equals(values.get("remember_password")); }
    public synchronized String getRememberedPhone() { return string(values.get("remembered_phone")); }
    public synchronized String getRememberedPassword() { return isRememberPassword()?string(values.get("remembered_password")):""; }
    public synchronized Map<String,Object> getUserProfile() { return map(values.get("user")); }
    public synchronized Map<String,Object> getQuota() { return map(values.get("quota")); }
    public synchronized Map<String,Object> getPolicy() { return map(values.get("policy")); }
    public synchronized String getTokenValidUntil() { return string(values.get("token_valid_until")); }
    private void save(Map<String,Object> next) throws IOException {
        if(!storageReady) throw new IOException("账号安全存储尚未就绪；未覆盖旧配置");
        config.save(next); values=next;
    }
    public synchronized void setEnabled(boolean enabled) throws IOException {
        var next=new LinkedHashMap<>(values);next.put("typeless_enabled",enabled);save(next);status=readyStatus();
    }
    public synchronized void remember(String phone,String password,boolean remember) throws IOException {
        var next=new LinkedHashMap<>(values);next.put("remember_password",remember);next.put("remembered_phone",phone);
        next.put("remembered_password",remember?password:"");save(next);
    }
    public synchronized boolean authenticate(long g,String token,String phone,String password,boolean remember) throws IOException {
        if(g!=generation)return false;
        var next=new LinkedHashMap<>(values);
        next.put("access_token",token);next.put("user",Map.of("phone",phone));next.put("quota",Map.of());next.put("policy",Map.of());next.remove("token_valid_until");
        next.put("remember_password",remember);next.put("remembered_phone",phone);next.put("remembered_password",remember?password:"");
        save(next);status=readyStatus();return true;
    }
    public synchronized void logout() throws IOException {
        serverExpiredOrigin=null;serverExpiredDelivery=null;++generation;
        var next=new LinkedHashMap<>(values);next.put("access_token","");next.remove("user");next.remove("quota");next.remove("policy");next.remove("token_valid_until");
        // Invalidate memory even if disk clearing fails; caller must report persistence failure.
        values=next;status="未登录";save(next);
    }
    public synchronized Session operationDelivery(Session origin){
        if(current(origin))return origin;
        return origin.equals(serverExpiredOrigin)&&serverExpiredDelivery!=null&&current(serverExpiredDelivery)?serverExpiredDelivery:origin;
    }
    synchronized void expired(Session s) throws IOException { if(current(s))logout(); }
    synchronized boolean update(Session s,JsonNode data) throws IOException {
        if(!current(s))return false;
        var next=new LinkedHashMap<>(values);
        JsonNode user=data.path("user").isObject()?data.path("user"):data.path("profile").isObject()?data.path("profile"):data;
        // Whitelist display fields: never persist arbitrary response credentials in the profile.
        var profile=new LinkedHashMap<>(getUserProfile());
        for(String key:List.of("phone","user_id","userId","id","name")) if(user.hasNonNull(key))profile.put(key,json.convertValue(user.get(key),Object.class));
        next.put("user",profile);
        var quota=new LinkedHashMap<>(getQuota());
        for(String period:List.of("daily","weekly","monthly"))for(String kind:List.of("used_","limit_")){
            String key=kind+period;JsonNode v=alias(data,key);if(v==null)v=alias(data.path("quota"),key);if(v==null)v=alias(user,key);
            Long number=integer(v==null?null:v.asText());if(number!=null&&number>=0)quota.put(key,number);
        }
        next.put("quota",quota);
        JsonNode policy=data.path("policy").isObject()?data.path("policy"):user.path("policy");
        if(policy.isObject()) {
            var p=new LinkedHashMap<String,Object>();
            for(String key:List.of("recharge_prices_fen","enable_daily","enable_weekly","enable_monthly")){
                JsonNode v=alias(policy,key);if(v!=null){
                    if(key.startsWith("enable_")){String flag=v.asText().trim();if(List.of("true","1").contains(flag))p.put(key,true);else if(List.of("false","0").contains(flag))p.put(key,false);}
                    else p.put(key,json.convertValue(v,Object.class));
                }
            }next.put("policy",p);
        }
        String until=firstText(data,"token_valid_until","tokenValidUntil","expires_at","expiresAt");
        if(until.isBlank())until=firstText(user,"token_valid_until","tokenValidUntil","expires_at","expiresAt");
        if(until.isBlank())until=firstText(data.path("quota"),"token_valid_until","tokenValidUntil","expires_at","expiresAt");
        if(!until.isBlank())next.put("token_valid_until",until);
        save(next);status=readyStatus();return true;
    }
    private String unavailableReason() {
        if(!isEnabled())return "开关已关闭";
        if(!hasValidToken())return "未登录或登录已失效";
        String until=getTokenValidUntil();
        if(!until.isBlank())try {
            Instant expiry;
            try{expiry=Instant.parse(until);}catch(DateTimeException e){long raw=Long.parseLong(until);expiry=raw<10_000_000_000L?Instant.ofEpochSecond(raw):Instant.ofEpochMilli(raw);}
            if(!expiry.isAfter(clock.instant()))return "服务已到期";
        }catch(RuntimeException invalid){return "服务有效期未能确认";}
        for(String period:List.of("daily","weekly","monthly")){
            Object limit=getQuota().get("limit_"+period),used=getQuota().get("used_"+period);
            if(!Boolean.FALSE.equals(getPolicy().get("enable_"+period))&&limit instanceof Number l&&used instanceof Number u&&l.longValue()>0&&u.longValue()>=l.longValue())return "额度不足";
        }
        return null;
    }
    public synchronized String readyStatus() {
        String reason=unavailableReason();
        return reason!=null?"AhaType "+reason:getQuota().isEmpty()?"AhaType 未就绪（额度未获取）":"AhaType 已启用（以实际处理结果为准）";
    }
    public ProcessResult process(String original) {
        Session s;String fallback;
        synchronized(this){s=session();fallback=unavailableReason();if(fallback==null)status="AhaType 正在整理文字…";}
        if(fallback!=null)return fallback(original,fallback,s);
        try {
            JsonNode data=request("/api/v1/typeless/process","POST",Map.of("text",original),s).path("data");
            String output=firstText(data,"text","result");
            if(output.isBlank())return fallback(original,"云端返回空文字",s);
            synchronized(this){if(!current(s))return fallback(original,"账号已变化",s);status="AhaType 整理完成";}
            return new ProcessResult(output,"AhaType 整理完成",()->current(s));
        }catch(CloudFailure e){
            // A server-expired session still falls back for this recording; an explicit logout
            // or account switch must instead invalidate delivery, including error paths.
            return e.fallbackSession!=null?fallback(original,e.getMessage(),e.fallbackSession):fallback(original,e.getMessage(),s);
        }
        catch(InterruptedException e){Thread.currentThread().interrupt();return fallback(original,"整理已中断",s);}
        catch(Exception e){return fallback(original,e instanceof HttpTimeoutException?"云端请求超时":"网络或响应异常",s);}
    }
    private synchronized ProcessResult fallback(String text,String reason,Session s){String message="已使用原文："+reason;if(current(s))status=message;return new ProcessResult(text,message,()->current(s));}
    JsonNode request(String path,String method,Map<String,?> body,Session s) throws Exception {
        if(s!=null&&!current(s))throw new CloudFailure("账号已变化，旧请求已作废",false);
        HttpRequest.Builder b=HttpRequest.newBuilder(URI.create(base.toString().replaceAll("/+$","")+path)).timeout(REQUEST_TIMEOUT).header("Content-Type","application/json; charset=utf-8");
        if(s!=null)b.header("Authorization","Bearer "+s.token());
        if(method.equals("GET"))b.GET();else b.POST(HttpRequest.BodyPublishers.ofString(json.writeValueAsString(body)));
        HttpResponse<String> response=http.send(b.build(),HttpResponse.BodyHandlers.ofString());
        JsonNode root;
        try{root=json.readTree(response.body());}catch(Exception e){throw new CloudFailure("云端响应异常",false);}
        String code=root==null?"":root.path("code").asText().trim();
        if(response.statusCode()==401||response.statusCode()==403||code.equals("401")||(root!=null&&root.path("data").asText().equals("401"))){
            Session invalidated=null;
            synchronized(this){if(s!=null&&current(s)){try{logout();}catch(IOException e){status="登录已失效，但本地会话清除失败";}invalidated=session();serverExpiredOrigin=s;serverExpiredDelivery=invalidated;}else if(s!=null){Session delivery=operationDelivery(s);if(current(delivery))invalidated=delivery;}}
            throw new CloudFailure("登录已失效，请重新登录",true,invalidated);
        }
        if(response.statusCode()!=200||root==null||!root.isObject()||(!code.equals("0")&&!code.equals("200"))){
            if(response.statusCode()==402||response.statusCode()==429)throw new CloudFailure("服务到期或额度不足",false);
            // Do not expose arbitrary server bodies, tokens, passwords or coupon codes.
            throw new CloudFailure(response.statusCode()>=500?"云端服务暂不可用":"请求被拒绝，请核对输入或账号权益",false);
        }
        return root;
    }
    public static final class CloudFailure extends IOException {
        public final boolean expired;
        final Session fallbackSession;
        CloudFailure(String message,boolean expired){this(message,expired,null);}
        CloudFailure(String message,boolean expired,Session fallbackSession){super(message);this.expired=expired;this.fallbackSession=fallbackSession;}
    }
    static JsonNode data(JsonNode root){return root.path("data").isObject()?root.path("data"):root;}
    static String firstText(JsonNode node,String...names){if(node!=null)for(String name:names){JsonNode n=node.get(name);if(n!=null&&(n.isTextual()||n.isNumber())&&!n.asText().isBlank())return n.asText();}return "";}
    static JsonNode alias(JsonNode node,String key){if(node==null)return null;JsonNode n=node.get(key);if(n!=null&&!n.isNull())return n;StringBuilder c=new StringBuilder();boolean upper=false;for(char x:key.toCharArray()){if(x=='_')upper=true;else{c.append(upper?Character.toUpperCase(x):x);upper=false;}}return node.get(c.toString());}
    static String string(Object o){return o==null?"":String.valueOf(o);}
    static Long integer(Object o){try{return Long.valueOf(string(o).trim());}catch(NumberFormatException e){return null;}}
    static Map<String,Object> map(Object o){var m=new LinkedHashMap<String,Object>();if(o instanceof Map<?,?> a)a.forEach((k,v)->m.put(String.valueOf(k),v));return m;}
}
