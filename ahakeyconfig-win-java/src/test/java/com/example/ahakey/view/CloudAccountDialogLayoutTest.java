package com.example.ahakey.view;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CloudAccountDialogLayoutTest {
    @Test
    void initialSizeFitsTheAccountActionsAndLoginForm() {
        assertTrue(CloudAccountDialog.INITIAL_WIDTH >= 500);
        assertTrue(CloudAccountDialog.INITIAL_HEIGHT >= 360);
        double actionRowWidth = 4 * CloudAccountDialog.ACCOUNT_ACTION_MIN_WIDTH
            + 3 * 8 + 2 * 18;
        assertTrue(actionRowWidth <= CloudAccountDialog.INITIAL_WIDTH);
        assertEquals(CloudAccountDialog.INITIAL_WIDTH,
            CloudAccountDialog.renderDimension(Double.NaN, false,
                CloudAccountDialog.INITIAL_WIDTH));
        assertEquals(CloudAccountDialog.INITIAL_HEIGHT,
            CloudAccountDialog.renderDimension(Double.NaN, false,
                CloudAccountDialog.INITIAL_HEIGHT));
    }

    @Test
    void rerenderPreservesTheOpenWindowSize() {
        assertEquals(720,
            CloudAccountDialog.renderDimension(720, true,
                CloudAccountDialog.INITIAL_WIDTH));
        assertEquals(520,
            CloudAccountDialog.renderDimension(520, true,
                CloudAccountDialog.INITIAL_HEIGHT));
    }
}
