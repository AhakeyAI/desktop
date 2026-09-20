package com.example.ahakey.view;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TopBarAhaTypeTest {
    @Test
    void opensAccountOnlyForAnUnfulfilledEnableRequestThatNeedsLogin() {
        assertTrue(TopBar.shouldOpenCloudAccountOnAhaTypeToggle(true, false, true));
        assertFalse(TopBar.shouldOpenCloudAccountOnAhaTypeToggle(true, false, false));
        assertFalse(TopBar.shouldOpenCloudAccountOnAhaTypeToggle(true, true, true));
        assertFalse(TopBar.shouldOpenCloudAccountOnAhaTypeToggle(false, false, true));
    }
}
