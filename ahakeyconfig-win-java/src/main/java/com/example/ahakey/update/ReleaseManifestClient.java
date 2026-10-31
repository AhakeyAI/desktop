package com.example.ahakey.update;

import java.io.*;
import java.net.URI;
import java.net.http.*;
import java.time.Duration;
import java.util.Set;
import java.util.concurrent.*;

public final class ReleaseManifestClient {
    public static final URI STABLE = URI.create("https://ahakey.com/stable.json");
    // Sealed local allowlist. A manifest cannot authorize another host or downgrade TLS.
    private static final Set<String> HOSTS = Set.of("ahakey.com", "7072-prod-0gkk7gxj94d927df-1398334410.tcb.qcloud.la");
    private static final ScheduledExecutorService TIMEOUTS = Executors.newSingleThreadScheduledExecutor(r -> { Thread t = new Thread(r, "update-deadlines"); t.setDaemon(true); return t; });
    public record Response(int status, long contentLength, InputStream body) implements AutoCloseable { public void close() throws IOException { body.close(); } }
    @FunctionalInterface public interface Transport { Response get(URI uri) throws Exception; }
    public record HopResponse(int status,long contentLength,InputStream body,String location) {}
    @FunctionalInterface public interface HopTransport { HopResponse get(URI uri)throws Exception; }
    private final Transport transport;
    public ReleaseManifestClient() { this(httpTransport()); }
    public ReleaseManifestClient(Transport transport) { this.transport = transport; }
    public static void requireAllowedUrl(URI uri) throws IOException {
        if (uri == null || !"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null
                || !HOSTS.contains(uri.getHost().toLowerCase(java.util.Locale.ROOT)) || uri.getUserInfo() != null
                || uri.getFragment() != null || (uri.getPort() != -1 && uri.getPort() != 443)) throw new IOException("更新链接不在可信 HTTPS 来源内。");
    }
    public static Transport httpTransport() {
        HttpClient client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).followRedirects(HttpClient.Redirect.NEVER).build();
        return redirecting(uri->{
            try {
                var response=client.send(HttpRequest.newBuilder(uri).timeout(Duration.ofSeconds(30)).GET().build(),HttpResponse.BodyHandlers.ofInputStream());
                return new HopResponse(response.statusCode(),response.headers().firstValueAsLong("Content-Length").orElse(-1),response.body(),response.headers().firstValue("Location").orElse(null));
            }catch(InterruptedException e){Thread.currentThread().interrupt();throw new IOException("更新请求已中断。");}
            catch(Exception e){throw new IOException("更新服务器连接失败或超时。");}
        });
    }
    public static Transport redirecting(HopTransport transport) {
        return uri -> {
            URI current=uri;
            for(int hop=0;hop<=3;hop++){
                requireAllowedUrl(current);
                HopResponse response=transport.get(current);
                if(Set.of(301,302,303,307,308).contains(response.status())){
                    response.body().close();
                    if(uri.equals(STABLE)||hop==3)throw new IOException("更新来源重定向不受支持");
                    String location=response.location();if(location==null||location.isBlank())throw new IOException("下载重定向缺少目标");
                    try{current=current.resolve(location);}catch(IllegalArgumentException e){throw new IOException("下载重定向无效");}
                    continue;
                }
                return new Response(response.status(),response.contentLength(),response.body());
            }
            throw new IOException("下载重定向过多");
        };
    }
    public static ScheduledFuture<?> closeAfter(InputStream stream, Duration timeout) {
        return TIMEOUTS.schedule(() -> { try { stream.close(); } catch (IOException ignored) {} }, timeout.toMillis(), TimeUnit.MILLISECONDS);
    }
    public ReleaseManifest fetch() throws Exception {
        try (Response response = transport.get(STABLE)) {
            if (response.status == 404) throw new IOException("更新信息尚未发布或暂不可用（HTTP 404）。");
            if (response.status != 200) throw new IOException("无法获取更新信息（HTTP " + response.status + "）。");
            if (response.contentLength > 1024 * 1024) throw new IOException("更新目录过大。");
            var deadline = closeAfter(response.body, Duration.ofSeconds(30));
            try {
                byte[] bytes = response.body.readNBytes(1024 * 1024 + 1);
                if (bytes.length > 1024 * 1024 || (response.contentLength >= 0 && bytes.length != response.contentLength)) throw new IOException("更新目录长度无效。");
                return ReleaseManifest.parse(bytes);
            } finally { deadline.cancel(false); }
        }
    }
}
