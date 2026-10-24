package com.example.ahakey.model;

import javafx.beans.property.IntegerProperty;
import javafx.beans.property.SimpleIntegerProperty;
import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;

/** 单 Mode 的 OLED 动图草稿（对齐 Swift `AhaKeyOLEDDraft` 子集）。 */
public class OledModeDraft {
    private final StringProperty localAssetPath = new SimpleStringProperty(null);
    private final IntegerProperty framesPerSecond = new SimpleIntegerProperty(10);
    private final IntegerProperty frameCount = new SimpleIntegerProperty(0);
    private final StringProperty statusLine = new SimpleStringProperty("未上传");
    private final StringProperty captionLine = new SimpleStringProperty("等待 GIF");

    public StringProperty localAssetPathProperty() {
        return localAssetPath;
    }

    public String getLocalAssetPath() {
        return localAssetPath.get();
    }

    public void setLocalAssetPath(String path) {
        localAssetPath.set(path);
    }

    public IntegerProperty framesPerSecondProperty() {
        return framesPerSecond;
    }

    public int getFramesPerSecond() {
        return framesPerSecond.get();
    }

    public void setFramesPerSecond(int fps) {
        framesPerSecond.set(Math.max(1, Math.min(30, fps)));
    }

    public int getFrameCount() {
        return frameCount.get();
    }

    public void setFrameCount(int count) {
        frameCount.set(count);
    }

    public String getStatusLine() {
        return statusLine.get();
    }

    public void setStatusLine(String line) {
        statusLine.set(line);
    }

    public String getCaptionLine() {
        return captionLine.get();
    }

    public void setCaptionLine(String line) {
        captionLine.set(line);
    }
}
