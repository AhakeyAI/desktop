package com.example.ahakey.service;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

class UsbHidInterfaceSelectionTest {

    // Order as Windows listed them on a real machine: consumer control first.
    static final String KEYBOARD =
        "\\\\?\\hid#vid_413c&pid_2107&mi_00&col01#7&392fbd74&0&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}";
    static final String CONSUMER =
        "\\\\?\\hid#vid_413c&pid_2107&mi_00&col02#7&392fbd74&0&0001#{4d1e55b2-f16f-11cf-88cb-001111000030}";
    static final String CONFIG =
        "\\\\?\\hid#vid_413c&pid_2107&mi_01#7&2bc370bc&0&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}";

    @Test
    void picksTheConfigInterfaceEvenWhenMediaKeysAreListedFirst() {
        assertEquals(CONFIG, UsbHidTransport.selectConfigInterface(List.of(KEYBOARD, CONSUMER, CONFIG)));
    }

    @Test
    void neverFallsBackToKeyboardOrMediaKeyInterfaces() {
        assertNull(UsbHidTransport.selectConfigInterface(List.of(KEYBOARD, CONSUMER)));
        assertNull(UsbHidTransport.selectConfigInterface(List.of()));
    }
}
