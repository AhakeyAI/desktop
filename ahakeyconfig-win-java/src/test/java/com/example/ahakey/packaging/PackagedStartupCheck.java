package com.example.ahakey.packaging;

import com.example.ahakey.App;
import javafx.application.Application;
import javafx.stage.Stage;

/** Explicit desktop smoke check: run with the packaged JVM/JAR/libs, not the developer JDK.
 * Opens the real main window, then exits. Does not record audio or send device commands.
 */
public final class PackagedStartupCheck {
    public static final class ProbeApp extends App {
        @Override public void start(Stage stage) {
            try {
                super.start(stage);
                if (!stage.isShowing()) throw new AssertionError("Main window did not open");
                stage.getScene().getRoot().applyCss();
                stage.getScene().getRoot().layout();
                System.out.println("PASS packaged main window opened and laid out");
                System.exit(0);
            } catch (Throwable failure) {
                failure.printStackTrace();
                System.exit(1);
            }
        }
        // The production stop() exits with 0, which would mask a startup failure.
        @Override public void stop() { }
    }
    public static void main(String[] args) { Application.launch(ProbeApp.class, args); }
}
