package com.example.ahakey.view;

import com.example.ahakey.model.KeyConfig;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SavePreviewDialogTest {
    @Test
    void listsTheTwelveWrittenBindingsAndLeavesOutTheDesktopOnlyVoiceKey() {
        List<SavePreviewDialog.Row> rows = SavePreviewDialog.rows(new StudioState());
        assertEquals(12, rows.size());
        assertEquals("K2", rows.get(0).key());
        assertEquals("K4", rows.get(2).key());
        assertEquals(ModeSlot.values()[1].getShortName(), rows.get(3).mode());
        assertTrue(rows.stream().noneMatch(row -> row.key().equals("K1")));
    }

    @Test
    void describesShortcutsMacrosAndEmptyKeys() {
        StudioState state = new StudioState();
        KeyConfig shortcut = state.getKeyConfig(ModeSlot.values()[0], StudioPart.KEY2);
        shortcut.setHidCode(0x200 | 0x06); // Ctrl+C
        shortcut.setDescription("Copy");
        assertEquals("Ctrl+C  ·  Copy", SavePreviewDialog.describe(shortcut));

        KeyConfig macro = new KeyConfig(0, "");
        macro.addMacroStep("DOWN_KEY", 0x04);
        assertTrue(SavePreviewDialog.describe(macro).contains("A"));

        assertTrue(SavePreviewDialog.describe(new KeyConfig(0, "")).length() > 0);
    }
}
