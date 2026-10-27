package com.example.ahakey.update;

import java.io.*;
import java.net.URI;
import java.nio.file.*;
import java.security.*;
import java.time.Duration;
import java.util.HexFormat;
import java.util.concurrent.CancellationException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.LongConsumer;

public final class VerifiedDownload {
    private final ReleaseManifestClient.Transport transport;
    private final AtomicBoolean cancelled = new AtomicBoolean();
    private volatile InputStream stream;
    public VerifiedDownload() { this(ReleaseManifestClient.httpTransport()); }
    public VerifiedDownload(ReleaseManifestClient.Transport transport) { this.transport = transport; }
    public boolean isCancelled() { return cancelled.get(); }
    public void cancel() { cancelled.set(true); InputStream in = stream; if (in != null) try { in.close(); } catch (IOException ignored) {} }
    public Path fetch(URI url, long size, String hash, Path directory, String suffix, LongConsumer progress) throws Exception {
        ReleaseManifestClient.requireAllowedUrl(url);
        boolean untrustedLength = size == -1 && hash.isEmpty() && suffix.equals(".exe");
        if ((!untrustedLength && (size <= 0 || size > ReleaseSignature.MAX_FILE || !hash.matches("[a-f0-9]{64}"))) || !suffix.matches("\\.(exe|hex)")) throw new IOException("下载身份无效。");
        Files.createDirectories(directory);
        Path part = Files.createTempFile(directory, "download-", ".part"), complete = part.resolveSibling(part.getFileName() + suffix);
        boolean success = false;
        try (var response = transport.get(url)) {
            if (response.status() != 200 || response.contentLength() > ReleaseSignature.MAX_FILE
                    || (!untrustedLength && response.contentLength() >= 0 && response.contentLength() != size)) throw new IOException("下载状态或文件长度不匹配。");
            stream = response.body();
            var deadline = ReleaseManifestClient.closeAfter(stream, Duration.ofMinutes(20));
            try (OutputStream out = Files.newOutputStream(part)) {
                MessageDigest digest = MessageDigest.getInstance("SHA-256"); byte[] buffer = new byte[65536]; long total = 0;
                int n;
                while (true) {
                    checkCancelled(); n = stream.read(buffer); if (n < 0) break;
                    total += n; if (total > (untrustedLength ? ReleaseSignature.MAX_FILE : size)) throw new IOException("下载文件超出大小限制。");
                    digest.update(buffer, 0, n); out.write(buffer, 0, n); progress.accept(total);
                }
                checkCancelled();
                if (total == 0 || (response.contentLength() >= 0 && total != response.contentLength())
                        || (!untrustedLength && (total != size || !HexFormat.of().formatHex(digest.digest()).equals(hash)))) throw new IOException("下载文件长度或 SHA256 校验失败。");
            } finally { deadline.cancel(false); stream = null; }
            checkCancelled(); Files.move(part, complete, StandardCopyOption.ATOMIC_MOVE); success = true; return complete;
        } finally { stream = null; Files.deleteIfExists(part); if (!success) Files.deleteIfExists(complete); }
    }
    private void checkCancelled() { if (cancelled.get() || Thread.currentThread().isInterrupted()) throw new CancellationException("下载已取消。"); }
    public static String sha256(Path file) throws IOException {
        try (InputStream in = Files.newInputStream(file)) { MessageDigest d = MessageDigest.getInstance("SHA-256"); byte[] b = new byte[65536]; int n; while ((n = in.read(b)) >= 0) d.update(b, 0, n); return HexFormat.of().formatHex(d.digest()); }
        catch (NoSuchAlgorithmException e) { throw new AssertionError(e); }
    }
}
