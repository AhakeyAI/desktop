package com.example.ahakey.localvoice;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;

/**
 * On-disk layout of the downloaded local voice pack.
 *
 * <pre>
 * %LOCALAPPDATA%\AhaKeyStudio\local-voice\
 *   installed.json            which pack is active, with file sizes and hashes
 *   packs\&lt;packId&gt;\models\...  recognition models
 *   packs\&lt;packId&gt;\native\win-x64\...  Sherpa / ONNX Runtime DLLs
 *   staging\&lt;packId&gt;\...       partial downloads, kept so a retry can resume
 * </pre>
 *
 * {@code installed.json} is written last, so a pack only counts as installed
 * after every file has been downloaded and verified.
 */
public final class LocalVoiceAssets {

    private static final Logger logger = LoggerFactory.getLogger(LocalVoiceAssets.class);
    private static final ObjectMapper MAPPER = new ObjectMapper()
        .enable(SerializationFeature.INDENT_OUTPUT);
    private static final String INSTALLED_FILE = "installed.json";

    private final Path root;

    public LocalVoiceAssets(Path root) {
        this.root = root.toAbsolutePath().normalize();
    }

    public static Path defaultRoot() {
        String localAppData = System.getenv("LOCALAPPDATA");
        if (localAppData != null && !localAppData.isBlank()) {
            return Path.of(localAppData, "AhaKeyStudio", "local-voice");
        }
        return Path.of(System.getProperty("user.home"), ".ahakey", "local-voice");
    }

    public Path root() {
        return root;
    }

    Path packsDir() {
        return root.resolve("packs");
    }

    Path stagingDir(String packId) {
        return root.resolve("staging").resolve(packId);
    }

    /** A verified, complete pack on disk. */
    public record InstalledPack(String packId, Path directory) {
        public Path modelDirectory() {
            return directory.resolve("models");
        }

        public Path nativeDirectory() {
            return directory.resolve("native").resolve("win-x64");
        }
    }

    /**
     * Returns the active pack if its record exists and every recorded file is
     * still present with the recorded size. Hashes were checked at install time
     * and are not recomputed on every start.
     */
    public Optional<InstalledPack> installed() {
        Path record = root.resolve(INSTALLED_FILE);
        if (!Files.isRegularFile(record)) return Optional.empty();
        try {
            Installed installed = MAPPER.readValue(record.toFile(), Installed.class);
            if (installed.packId == null || installed.files == null || installed.files.isEmpty()) {
                return Optional.empty();
            }
            Path packDir = packsDir().resolve(installed.packId).normalize();
            if (!packDir.startsWith(packsDir())) return Optional.empty();
            List<String> paths = new ArrayList<>();
            for (InstalledFile file : installed.files) {
                Path path = packDir.resolve(file.path).normalize();
                if (!path.startsWith(packDir) || !Files.isRegularFile(path)
                    || Files.size(path) != file.size) {
                    logger.warn("Local voice pack {} is incomplete: {}", installed.packId, file.path);
                    return Optional.empty();
                }
                paths.add(file.path);
            }
            if (!paths.containsAll(LocalVoiceManifest.REQUIRED_PATHS)) return Optional.empty();
            return Optional.of(new InstalledPack(installed.packId, packDir));
        } catch (IOException | RuntimeException e) {
            logger.warn("installed.json could not be read: {}", e.getMessage());
            return Optional.empty();
        }
    }

    /** True when this exact manifest is already installed. */
    public boolean isInstalled(LocalVoiceManifest manifest) {
        return installed().map(pack -> pack.packId().equals(manifest.packId())).orElse(false);
    }

    /**
     * Moves a fully verified staging directory into place and records it as the
     * active pack. Older packs are removed on a best-effort basis.
     */
    void commit(LocalVoiceManifest manifest, Path verifiedStaging) throws IOException {
        Path target = packsDir().resolve(manifest.packId());
        Files.createDirectories(packsDir());
        if (Files.exists(target)) {
            // A pack deleted earlier in this session can leave DLLs that are
            // still loaded (Windows cannot delete them). Merge file by file:
            // identical files stay, everything else is replaced.
            for (LocalVoiceManifest.FileEntry entry : manifest.files()) {
                Path staged = verifiedStaging.resolve(entry.path()).normalize();
                Path dest = target.resolve(entry.path()).normalize();
                Files.createDirectories(dest.getParent());
                if (Files.isRegularFile(dest) && LocalVoiceInstaller.matches(dest, entry)) {
                    Files.deleteIfExists(staged);
                } else {
                    Files.move(staged, dest, StandardCopyOption.REPLACE_EXISTING);
                }
            }
            deleteTreeBestEffort(verifiedStaging);
        } else {
            try {
                Files.move(verifiedStaging, target, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException e) {
                Files.move(verifiedStaging, target);
            }
        }
        Installed installed = new Installed();
        installed.packId = manifest.packId();
        installed.files = new ArrayList<>();
        for (LocalVoiceManifest.FileEntry entry : manifest.files()) {
            InstalledFile file = new InstalledFile();
            file.path = entry.path();
            file.size = entry.size();
            file.sha256 = entry.sha256();
            installed.files.add(file);
        }
        writeAtomically(root.resolve(INSTALLED_FILE), installed);
        removeUnusedPacks(manifest.packId());
    }

    /**
     * Forgets the installed pack and deletes its files. DLLs that are still
     * loaded by this process cannot be deleted on Windows; those are removed by
     * {@link #removeUnusedPacks} on a later start.
     */
    public void uninstall() throws IOException {
        Files.deleteIfExists(root.resolve(INSTALLED_FILE));
        removeUnusedPacks(null);
        deleteTreeBestEffort(root.resolve("staging"));
    }

    /** Deletes every pack except {@code keepPackId}; locked files are skipped. */
    public void removeUnusedPacks(String keepPackId) {
        Path packs = packsDir();
        if (!Files.isDirectory(packs)) return;
        try (DirectoryStream<Path> entries = Files.newDirectoryStream(packs)) {
            for (Path pack : entries) {
                if (keepPackId != null && pack.getFileName().toString().equals(keepPackId)) continue;
                deleteTreeBestEffort(pack);
            }
        } catch (IOException e) {
            logger.debug("Could not list local voice packs: {}", e.getMessage());
        }
    }

    private static void writeAtomically(Path file, Object value) throws IOException {
        Files.createDirectories(file.getParent());
        Path temporary = file.resolveSibling(file.getFileName() + ".tmp");
        MAPPER.writeValue(temporary.toFile(), value);
        try {
            Files.move(temporary, file, StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE);
        } catch (AtomicMoveNotSupportedException e) {
            Files.move(temporary, file, StandardCopyOption.REPLACE_EXISTING);
        }
    }

    static void deleteTree(Path directory) throws IOException {
        if (!Files.exists(directory)) return;
        try (Stream<Path> walk = Files.walk(directory)) {
            for (Path path : walk.sorted(Comparator.reverseOrder()).toList()) {
                Files.deleteIfExists(path);
            }
        }
    }

    static void deleteTreeBestEffort(Path directory) {
        if (!Files.exists(directory)) return;
        try (Stream<Path> walk = Files.walk(directory)) {
            for (Path path : walk.sorted(Comparator.reverseOrder()).toList()) {
                try {
                    Files.deleteIfExists(path);
                } catch (IOException e) {
                    logger.debug("Left in place (probably in use): {}", path);
                }
            }
        } catch (IOException e) {
            logger.debug("Could not clean {}: {}", directory, e.getMessage());
        }
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    static final class Installed {
        public String packId;
        public List<InstalledFile> files;
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    static final class InstalledFile {
        public String path;
        public long size;
        public String sha256;
    }
}
