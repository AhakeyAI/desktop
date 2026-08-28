package com.example.ahakey.firmware;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;

class IntelHexValidatorTest {
    @TempDir Path temp;

    @Test
    void acceptsStructurallyValidIntelHex() throws Exception {
        Path hex = temp.resolve("firmware.hex");
        Files.writeString(hex, ":0400000001020304F2\n:00000001FF\n");
        assertDoesNotThrow(() -> IntelHexValidator.validate(hex));
    }

    @Test
    void rejectsBadChecksumMissingEofAndRenamedGarbage() throws Exception {
        Path checksum = temp.resolve("checksum.hex");
        Files.writeString(checksum, ":0400000001020304F3\n:00000001FF\n");
        assertThrows(Exception.class, () -> IntelHexValidator.validate(checksum));

        Path noEof = temp.resolve("no-eof.hex");
        Files.writeString(noEof, ":0400000001020304F2\n");
        assertThrows(Exception.class, () -> IntelHexValidator.validate(noEof));

        Path garbage = temp.resolve("renamed.hex");
        Files.writeString(garbage, "not firmware");
        assertThrows(Exception.class, () -> IntelHexValidator.validate(garbage));
    }

    @Test
    void enforcesAbsoluteCh582AddressBoundsAndExtendedLinearAddress() throws Exception {
        Path legal = temp.resolve("legal-max.hex");
        Files.writeString(legal,
            ":020000040006F4\n:01FFFF00AA57\n:00000001FF\n");
        assertDoesNotThrow(() -> IntelHexValidator.validate(legal));

        Path beyond = temp.resolve("beyond.hex");
        Files.writeString(beyond,
            ":020000040007F3\n:01000000AA55\n:00000001FF\n");
        assertThrows(Exception.class, () -> IntelHexValidator.validate(beyond));

        Path overlap = temp.resolve("overlap.hex");
        Files.writeString(overlap,
            ":020000040000FA\n:020000000102FB\n:0100010003FB\n:00000001FF\n");
        assertThrows(Exception.class, () -> IntelHexValidator.validate(overlap));
    }
}
