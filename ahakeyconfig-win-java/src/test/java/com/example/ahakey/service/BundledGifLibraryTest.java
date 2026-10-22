package com.example.ahakey.service;

import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.protocol.AhaKeyProtocol;
import com.example.ahakey.util.OLEDFrameEncoder;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BundledGifLibraryTest {
    @Test
    void shipsAUsableFourByFourDefaultGifSet() throws Exception {
        for (ModeSlot mode : ModeSlot.values()) {
            for (int asset = 0; asset < AhaKeyProtocol.GIF_ASSET_COUNT; asset++) {
                assertNotNull(BundledGifLibrary.resource(mode, asset));
                var path = BundledGifLibrary.extract(mode, asset);
                int frames = OLEDFrameEncoder.frameCount(path);
                assertTrue(frames >= 1 && frames <= AhaKeyProtocol.gifAssetCapacity(asset),
                    mode + " asset " + asset + " has " + frames + " frames");
                var encoded = OLEDFrameEncoder.framesFromGif(path, frames);
                assertTrue(encoded.stream().allMatch(
                    frame -> frame.rgb565.length == AhaKeyProtocol.OLED_FRAME_BYTES));
            }
        }
    }
}
