package com.example.ahakey.service;

import com.example.ahakey.model.OledResourceState;
import com.example.ahakey.model.OledResourceState.Asset;
import com.example.ahakey.model.OledResourceState.LocalStatus;
import com.example.ahakey.model.OledResourceState.Metadata;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

/** Assets are immutable; the atomic index replacement is the commit point. */
public final class OledResourceStore {
    public static final class CleanupFailure extends IOException {
        public CleanupFailure(IOException cause) { super("本地索引已清除，但成品文件删除失败：" + cause.getMessage(), cause); }
    }
    private final Path root;
    private final ObjectMapper mapper = new ObjectMapper();
    private ObjectNode index;

    public OledResourceStore() { this(Path.of(System.getProperty("user.home"), ".ahakey", "oled-resources", "v1")); }
    public OledResourceStore(Path root) { this.root = root.toAbsolutePath().normalize(); }
    public Path root() { return root; }

    public synchronized Map<Integer, OledResourceState> load() throws IOException {
        index = null;
        if (Files.exists(root.resolve("index.json"))) {
            if (Files.size(root.resolve("index.json")) > 1024 * 1024) throw new IOException("本地资源库索引过大。");
            JsonNode parsed = mapper.readTree(root.resolve("index.json").toFile());
            if (!(parsed instanceof ObjectNode object) || object.path("version").asInt(-1) != 1 || !object.path("entries").isObject())
                throw new IOException("本地资源库索引格式无效，未覆盖原文件。");
            index = object;
        } else {
            index = mapper.createObjectNode();
            index.put("version", 1);
            index.putObject("entries");
        }
        Map<Integer, OledResourceState> states = new LinkedHashMap<>();
        try {
            for (int entry = 0; entry < 19; entry++) {
                JsonNode node = index.path("entries").path(Integer.toString(entry));
                if (node.isMissingNode()) { states.put(entry, OledResourceState.empty(entry)); continue; }
                Asset asset = null;
                if (node.hasNonNull("file")) {
                    Path path = assetPath(node.path("file").asText());
                    int frames = node.path("frames").asInt(-1);
                    if (frames < 1 || frames > 12 || Files.size(path) != frames * 28672L) throw new IOException("本地成品尺寸无效：目标 " + entry);
                    asset = new Asset(Files.readAllBytes(path), frames, node.path("crc").asLong(-1));
                }
                Metadata device = node.hasNonNull("device") ? mapper.treeToValue(node.get("device"), Metadata.class) : null;
                LocalStatus status = LocalStatus.valueOf(node.path("status").asText());
                boolean interrupted = node.path("inFlight").asBoolean();
                OledResourceState state = new OledResourceState(entry, asset, status, device, false, false,
                        node.path("commitUncertain").asBoolean(),
                        interrupted ? "上次上传被中断，设备保存结果未确认。" : node.path("notice").asText(""));
                if (interrupted) state = state.failed("上次上传被中断，设备保存结果未确认。", node.path("commitUncertain").asBoolean());
                states.put(entry, state);
            }
        } catch (IllegalArgumentException | IOException e) { index = null; throw new IOException("本地资源库内容无效：" + e.getMessage(), e); }
        return states;
    }

    public synchronized boolean containsEntry(int entry) throws IOException {
        requireLoaded();
        return index.path("entries").has(Integer.toString(entry));
    }

    public synchronized void save(OledResourceState state) throws IOException {
        requireLoaded();
        Files.createDirectories(root);
        ObjectNode next = index.deepCopy();
        ObjectNode entries = (ObjectNode) next.get("entries");
        JsonNode previous = entries.path(Integer.toString(state.entry()));
        ObjectNode record = mapper.createObjectNode();
        String file = null;
        if (state.asset() != null) {
            byte[] bytes = state.asset().bytes();
            if (previous.hasNonNull("file") && previous.path("crc").asLong(-1) == state.asset().crc()
                    && previous.path("frames").asInt(-1) == state.asset().frames()
                    && Files.exists(assetPath(previous.path("file").asText()))
                    && java.util.Arrays.equals(Files.readAllBytes(assetPath(previous.path("file").asText())), bytes)) {
                file = previous.path("file").asText();
            } else {
                file = state.entry() + "-" + UUID.randomUUID() + ".rgb565";
                atomicWrite(root.resolve(file), bytes);
            }
            record.put("file", file);
            record.put("frames", state.asset().frames());
            record.put("crc", state.asset().crc());
        }
        record.put("status", state.localStatus().name());
        record.put("inFlight", state.inFlight());
        record.put("commitUncertain", state.commitUncertain());
        record.put("notice", state.notice());
        record.set("device", mapper.valueToTree(state.device()));
        entries.set(Integer.toString(state.entry()), record);
        atomicWrite(root.resolve("index.json"), mapper.writerWithDefaultPrettyPrinter().writeValueAsBytes(next));
        index = next;
        // A cleared entry remains a tombstone so legacy migration cannot resurrect it.
        if (file == null && previous.hasNonNull("file")) {
            String old = previous.path("file").asText();
            boolean shared = false;
            for (JsonNode other : entries) if (old.equals(other.path("file").asText())) shared = true;
            if (!shared) {
                try { Files.deleteIfExists(assetPath(old)); }
                catch (IOException e) { throw new CleanupFailure(e); }
            }
        }
    }

    private void requireLoaded() throws IOException {
        if (index == null) throw new IOException("本地资源库尚未成功读取，禁止覆盖。");
    }
    private Path assetPath(String name) throws IOException {
        if (!name.matches("[0-9]{1,2}-[a-f0-9-]{36}\\.rgb565")) throw new IOException("本地成品路径无效。");
        Path path = root.resolve(name).normalize();
        if (!root.equals(path.getParent()) || Files.isSymbolicLink(path)) throw new IOException("本地成品路径越界。");
        return path;
    }
    private void atomicWrite(Path target, byte[] bytes) throws IOException {
        Path temporary = Files.createTempFile(root, ".pending-", ".tmp");
        try {
            try (FileChannel channel = FileChannel.open(temporary, StandardOpenOption.WRITE)) {
                ByteBuffer buffer = ByteBuffer.wrap(bytes);
                while (buffer.hasRemaining()) channel.write(buffer);
                channel.force(true);
            }
            Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        } finally { Files.deleteIfExists(temporary); }
    }
}
