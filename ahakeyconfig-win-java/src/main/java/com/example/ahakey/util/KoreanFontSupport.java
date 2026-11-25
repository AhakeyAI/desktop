package com.example.ahakey.util;

import java.net.URL;
import javafx.collections.ListChangeListener;
import javafx.scene.Scene;
import javafx.stage.Window;

/**
 * Korean UI uses Malgun Gothic, the Windows system font for Hangul. Segoe UI has
 * no Hangul glyphs, so without this the text falls back glyph by glyph.
 */
public final class KoreanFontSupport {
    public static final String FONT_FAMILY = "Malgun Gothic";
    private static final URL STYLESHEET = KoreanFontSupport.class.getResource("/style_ko.css");
    private static boolean installed;

    private KoreanFontSupport() {}

    /** Adds the Korean font stylesheet to every current and future window (dialogs included). */
    public static synchronized void installIfKorean() {
        if (installed || STYLESHEET == null || !LanguageManager.getInstance().isKorean()) return;
        installed = true;
        String css = STYLESHEET.toExternalForm();
        Window.getWindows().forEach(window -> attach(window, css));
        Window.getWindows().addListener((ListChangeListener<Window>) change -> {
            while (change.next()) {
                for (Window window : change.getAddedSubList()) attach(window, css);
            }
        });
    }

    /** Font family for code that sets fonts directly instead of through CSS. */
    public static String uiFontFamily(String defaultFamily) {
        return LanguageManager.getInstance().isKorean() ? FONT_FAMILY : defaultFamily;
    }

    private static void attach(Window window, String css) {
        addTo(window.getScene(), css);
        window.sceneProperty().addListener((observable, previous, scene) -> addTo(scene, css));
    }

    private static void addTo(Scene scene, String css) {
        if (scene != null && !scene.getStylesheets().contains(css)) scene.getStylesheets().add(css);
    }
}
