package com.example.ahakey.view;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.IDEState;
import com.example.ahakey.model.LightEffectStyle;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import javafx.animation.KeyFrame;
import javafx.animation.Timeline;
import javafx.beans.binding.Bindings;
import javafx.fxml.FXML;
import javafx.scene.control.Label;
import javafx.scene.image.Image;
import javafx.scene.image.ImageView;
import javafx.scene.layout.Region;
import javafx.scene.layout.StackPane;
import javafx.scene.shape.Rectangle;
import javafx.util.Duration;

public class CanvasController {
    
    @FXML
    private Label oledTitle;
    
    @FXML
    private Label oledCaption;

    @FXML
    private ImageView oledPreviewImage;
    
    @FXML
    private Label toggleLabel;

    @FXML
    private Label key1Caption;

    @FXML
    private Label key2Caption;

    @FXML
    private Label key3Caption;

    @FXML
    private Label key4Caption;

    @FXML
    private Label modeIcon;
    
    @FXML
    private StackPane lightBarCard;
    
    @FXML
    private StackPane oledCard;
    
    @FXML
    private StackPane key1Card;
    
    @FXML
    private StackPane key2Card;
    
    @FXML
    private StackPane key3Card;
    
    @FXML
    private StackPane key4Card;
    
    @FXML
    private StackPane toggleCard;
    
    @FXML
    private StackPane modeBadge;

    @FXML
    private Rectangle toggleThumb;
    
    @FXML
    private Region lightSeg1;
    
    @FXML
    private Region lightSeg2;
    
    @FXML
    private Region lightSeg3;
    
    @FXML
    private Region lightSeg4;
    
    private StudioState studioState;
    private DeviceStatus deviceStatus;
    private Timeline lightAnimation;
    private int animationFrame = 0;
    
    private static final String COLOR_ACTIVE = "#0a84ff";
    private static final String COLOR_DIM = "#6b7280";
    private static final String COLOR_CENTER = "#39c5cf";
    private static final String COLOR_BRIGHT = "#5ac8fa";
    private static final String COLOR_GREEN = "#34c759";
    private static final String COLOR_RED = "#ff453a";
    private static final String COLOR_AMBER = "#ff9f0a";
    
    public void initialize() {
        // 初始化时绑定事件
    }
    
    public void setStudioState(StudioState studioState) {
        this.studioState = studioState;
        bindEvents();
        refreshPreview();
        setStableLightPreview();
    }
    
    public void setDeviceStatus(DeviceStatus deviceStatus) {
        this.deviceStatus = deviceStatus;
        bindDeviceStatus();
    }
    
    private void bindDeviceStatus() {
        if (toggleLabel != null && deviceStatus != null) {
            toggleLabel.textProperty().bind(Bindings.createStringBinding(
                deviceStatus::getSwitchTitle,
                deviceStatus.switchStateProperty()
            ));
            deviceStatus.switchStateProperty().addListener((obs, old, value) -> refreshToggleThumb());
            refreshToggleThumb();
        }
    }
    
    private void bindEvents() {
        lightBarCard.setOnMouseClicked(e -> studioState.setSelectedPart(StudioPart.LIGHT_BAR));
        oledCard.setOnMouseClicked(e -> studioState.setSelectedPart(StudioPart.OLED));
        key1Card.setOnMouseClicked(e -> studioState.setSelectedPart(StudioPart.KEY1));
        key2Card.setOnMouseClicked(e -> studioState.setSelectedPart(StudioPart.KEY2));
        key3Card.setOnMouseClicked(e -> studioState.setSelectedPart(StudioPart.KEY3));
        key4Card.setOnMouseClicked(e -> studioState.setSelectedPart(StudioPart.KEY4));
        toggleCard.setOnMouseClicked(e -> studioState.setSelectedPart(StudioPart.TOGGLE_SWITCH));
        
        studioState.selectedPartProperty().addListener((obs, old, newPart) -> refreshHotspots());
        studioState.selectedModeProperty().addListener((obs, old, newMode) -> refreshPreview());
        studioState.dirtyCountProperty().addListener((obs, old, newVal) -> refreshHotspots());
        studioState.revisionProperty().addListener((obs, old, newVal) -> refreshPreview());
        studioState.lightBarPreviewProperty().addListener((obs, old, newVal) -> {
            refreshPreview();
            animationFrame = 0;
            setStableLightPreview();
        });
    }
    
    public void refreshPreview() {
        ModeSlot mode = studioState.getSelectedMode();
        if (oledTitle != null) {
            oledTitle.setText(studioState.getOledSummary());
        }
        if (oledCaption != null) {
            oledCaption.setText(studioState.getOledCaption());
        }
        refreshOledPreviewImage(mode);
        if (modeIcon != null) {
            modeIcon.setText(String.valueOf(mode.getIndex() + 1));
        }
        refreshKeyCaptions(mode);
        refreshHotspots();
    }

    private void refreshKeyCaptions(ModeSlot mode) {
        if (key1Caption != null) key1Caption.setText(studioState.getKeyConfig(mode, StudioPart.KEY1).getDescription());
        if (key2Caption != null) key2Caption.setText(studioState.getKeyConfig(mode, StudioPart.KEY2).getDescription());
        if (key3Caption != null) key3Caption.setText(studioState.getKeyConfig(mode, StudioPart.KEY3).getDescription());
        if (key4Caption != null) key4Caption.setText(studioState.getKeyConfig(mode, StudioPart.KEY4).getDescription());
    }

    private void refreshOledPreviewImage(ModeSlot mode) {
        if (oledPreviewImage == null) {
            return;
        }
        String path = studioState.getOledDraft(mode).getLocalAssetPath();
        if (path == null || path.isBlank()) {
            oledPreviewImage.setImage(null);
            oledPreviewImage.setVisible(false);
            if (oledTitle != null) oledTitle.setVisible(true);
            if (oledCaption != null) oledCaption.setVisible(true);
            return;
        }
        try {
            oledPreviewImage.setImage(new Image("file:" + path, 140, 80, true, true));
            oledPreviewImage.setVisible(true);
            if (oledTitle != null) oledTitle.setVisible(false);
            if (oledCaption != null) oledCaption.setVisible(false);
        } catch (Exception e) {
            oledPreviewImage.setImage(null);
            oledPreviewImage.setVisible(false);
            if (oledTitle != null) oledTitle.setVisible(true);
            if (oledCaption != null) oledCaption.setVisible(true);
        }
    }

    private void refreshToggleThumb() {
        if (toggleThumb == null || deviceStatus == null) {
            return;
        }
        toggleThumb.setTranslateY(deviceStatus.isAutoApproval() ? -13 : 13);
    }

    private void setStableLightPreview() {
        if (lightSeg1 != null) {
            setAll(COLOR_DIM, 0.45);
        }
    }
    
    private void refreshHotspots() {
        refreshHotspot(lightBarCard, StudioPart.LIGHT_BAR);
        refreshHotspot(oledCard, StudioPart.OLED);
        refreshHotspot(key1Card, StudioPart.KEY1);
        refreshHotspot(key2Card, StudioPart.KEY2);
        refreshHotspot(key3Card, StudioPart.KEY3);
        refreshHotspot(key4Card, StudioPart.KEY4);
        refreshHotspot(toggleCard, StudioPart.TOGGLE_SWITCH);
    }
    
    private void refreshHotspot(StackPane hotspot, StudioPart part) {
        hotspot.getStyleClass().removeAll("selected-hotspot", "dirty-hotspot");
        if (part == studioState.getSelectedPart()) {
            hotspot.getStyleClass().add("selected-hotspot");
        }
        if (studioState.isDirty(part)) {
            hotspot.getStyleClass().add("dirty-hotspot");
        }
    }
    
    private void startLightAnimation() {
        if (lightAnimation != null) {
            lightAnimation.stop();
        }
        
        lightAnimation = new Timeline(new KeyFrame(Duration.millis(150), event -> {
            updateLightEffect();
            animationFrame++;
        }));
        lightAnimation.setCycleCount(Timeline.INDEFINITE);
        lightAnimation.play();
    }
    
    private void updateLightEffect() {
        if (studioState == null || lightSeg1 == null) {
            return;
        }
        
        LightEffectStyle effect = currentLightEffect();
        switch (effect) {
            case OFF -> setAll("#111827", 0.25);
            case BREATHING, APPROVAL_WAIT -> updateBreathingEffect(COLOR_BRIGHT);
            case MIDDLE_LIGHT, BLUE_THINKING -> updateMiddleLightEffect();
            case WARNING_BLINK, LOW_BATTERY -> updateBlinkEffect(COLOR_RED);
            case SUCCESS_SWEEP -> updateSweepEffect(COLOR_GREEN);
            case TYPING_RIPPLE, PULSE_CENTER -> updatePulseCenterEffect();
            case SCAN_BAR -> updateScanEffect(COLOR_AMBER);
            case CHARGING_FLOW -> updateScanEffect(COLOR_GREEN);
            case RAINBOW_MOVE, RAINBOW_WAVE, RAINBOW_WAVE_SLOW -> updateRainbowEffect();
            case SINGLE_MOVE, COMET -> updateSingleMoveEffect();
            default -> updateSingleMoveEffect();
        }
    }

    private LightEffectStyle currentLightEffect() {
        IDEState state = studioState.getLightBarPreview().getIdeState();
        return studioState.getAiLightEffect(studioState.getSelectedMode(), state);
    }
    
    private void updateSingleMoveEffect() {
        int position = animationFrame % 8;
        double[] brightness = new double[4];
        
        if (position < 4) {
            brightness[position] = 1.0;
            if (position > 0) brightness[position - 1] = 0.3;
            if (position < 3) brightness[position + 1] = 0.3;
        } else {
            int pos = 7 - position;
            brightness[pos] = 1.0;
            if (pos > 0) brightness[pos - 1] = 0.3;
            if (pos < 3) brightness[pos + 1] = 0.3;
        }
        
        setLightSegment(lightSeg1, brightness[0]);
        setLightSegment(lightSeg2, brightness[1]);
        setLightSegment(lightSeg3, brightness[2]);
        setLightSegment(lightSeg4, brightness[3]);
    }
    
    private void updateBreathingEffect(String color) {
        double phase = (animationFrame * Math.PI * 2) / 20;
        double brightness = (Math.sin(phase) + 1) / 2;
        
        setLightSegment(lightSeg1, color, brightness);
        setLightSegment(lightSeg2, color, brightness);
        setLightSegment(lightSeg3, color, brightness);
        setLightSegment(lightSeg4, color, brightness);
    }
    
    private void updateMiddleLightEffect() {
        setLightSegment(lightSeg1, 0.2);
        setLightSegment(lightSeg2, 1.0);
        setLightSegment(lightSeg3, 1.0);
        setLightSegment(lightSeg4, 0.2);
    }

    private void updateBlinkEffect(String color) {
        double b = (animationFrame % 6) < 3 ? 1.0 : 0.2;
        setAll(color, b);
    }

    private void updateSweepEffect(String color) {
        int lit = animationFrame % 5;
        setLightSegment(lightSeg1, color, lit >= 1 ? 1.0 : 0.2);
        setLightSegment(lightSeg2, color, lit >= 2 ? 1.0 : 0.2);
        setLightSegment(lightSeg3, color, lit >= 3 ? 1.0 : 0.2);
        setLightSegment(lightSeg4, color, lit >= 4 ? 1.0 : 0.2);
    }

    private void updatePulseCenterEffect() {
        double phase = (animationFrame * Math.PI * 2) / 16;
        double center = 0.4 + ((Math.sin(phase) + 1) / 2) * 0.6;
        setLightSegment(lightSeg1, COLOR_DIM, 0.25);
        setLightSegment(lightSeg2, COLOR_BRIGHT, center);
        setLightSegment(lightSeg3, COLOR_BRIGHT, center);
        setLightSegment(lightSeg4, COLOR_DIM, 0.25);
    }

    private void updateScanEffect(String color) {
        int position = animationFrame % 4;
        setLightSegment(lightSeg1, color, position == 0 ? 1.0 : 0.25);
        setLightSegment(lightSeg2, color, position == 1 ? 1.0 : 0.25);
        setLightSegment(lightSeg3, color, position == 2 ? 1.0 : 0.25);
        setLightSegment(lightSeg4, color, position == 3 ? 1.0 : 0.25);
    }

    private void updateRainbowEffect() {
        String[] colors = {"#ff453a", "#ff9f0a", "#34c759", "#0a84ff", "#bf5af2"};
        setLightSegment(lightSeg1, colors[(animationFrame + 0) % colors.length], 1.0);
        setLightSegment(lightSeg2, colors[(animationFrame + 1) % colors.length], 1.0);
        setLightSegment(lightSeg3, colors[(animationFrame + 2) % colors.length], 1.0);
        setLightSegment(lightSeg4, colors[(animationFrame + 3) % colors.length], 1.0);
    }

    private void setAll(String color, double brightness) {
        setLightSegment(lightSeg1, color, brightness);
        setLightSegment(lightSeg2, color, brightness);
        setLightSegment(lightSeg3, color, brightness);
        setLightSegment(lightSeg4, color, brightness);
    }
    
    private void setLightSegment(Region seg, double brightness) {
        if (brightness >= 1.0) {
            seg.setStyle("-fx-background-color: " + COLOR_BRIGHT + "; -fx-opacity: 1.0;");
        } else if (brightness >= 0.5) {
            seg.setStyle("-fx-background-color: " + COLOR_CENTER + "; -fx-opacity: " + brightness + ";");
        } else {
            seg.setStyle("-fx-background-color: " + COLOR_DIM + "; -fx-opacity: " + (0.3 + brightness * 0.4) + ";");
        }
    }

    private void setLightSegment(Region seg, String color, double brightness) {
        seg.setStyle("-fx-background-color: " + color + "; -fx-opacity: " + Math.max(0.15, Math.min(1.0, brightness)) + ";");
    }
    
    public void stopAnimation() {
        if (lightAnimation != null) {
            lightAnimation.stop();
        }
    }
}
