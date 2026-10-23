package com.example.ahakey.view;

import com.example.ahakey.model.DeviceStatus;
import com.example.ahakey.model.IDEState;
import com.example.ahakey.model.LightEffectStyle;
import com.example.ahakey.model.ModeSlot;
import com.example.ahakey.model.StudioPart;
import com.example.ahakey.model.StudioState;
import com.example.ahakey.util.LanguageManager;
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
    private Label lightBarLabel;
    
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
    @FXML private Region lightSeg5;
    @FXML private Region lightSeg6;
    @FXML private Region lightSeg7;
    @FXML private Region lightSeg8;
    @FXML private Label oledDraftBadge;
    
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
        if (lightBarLabel != null) {
            lightBarLabel.setText(LanguageManager.getInstance().getString("studio-part.light-bar"));
        }
    }
    
    public void setStudioState(StudioState studioState) {
        this.studioState = studioState;
        bindEvents();
        refreshPreview();
        setStableLightPreview();
        startLightAnimation();
        studioState.displayConfig().revision.addListener((o, a, b) -> refreshOledPreviewImage(studioState.getSelectedMode()));
        oledCard.sceneProperty().addListener((o, a, b) -> {
            if (b == null) stopAnimation(); else startLightAnimation();
        });
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
        oledCard.disableProperty().bind(studioState.displayConfig().busy);
        lightBarCard.disableProperty().bind(studioState.displayConfig().busy);
        key1Card.disableProperty().bind(studioState.uploadingOledProperty());
        key2Card.disableProperty().bind(studioState.uploadingOledProperty());
        key3Card.disableProperty().bind(studioState.uploadingOledProperty());
        key4Card.disableProperty().bind(studioState.uploadingOledProperty());
        toggleCard.disableProperty().bind(studioState.uploadingOledProperty());
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

    private com.example.ahakey.model.OledResourceState.Asset displayedAsset;
    private final java.util.List<javafx.scene.image.Image> oledFrames = new java.util.ArrayList<>();
    private int oledFrame;

    private void refreshOledPreviewImage(ModeSlot mode) {
        if (oledPreviewImage == null) return;
        var resource = studioState.displayConfig().current();
        if (resource.asset() != displayedAsset) {
            displayedAsset = resource.asset();
            oledFrames.clear();
            oledFrame = 0;
            if (displayedAsset != null) {
                byte[] bytes = displayedAsset.bytes();
                for (int i = 0; i < displayedAsset.frames(); i++) {
                    var decoded = com.example.ahakey.util.OLEDFrameEncoder.decodeFrame(bytes, i * 28672);
                    var image = new javafx.scene.image.WritableImage(160, 80);
                    for (int y = 0; y < 80; y++) for (int x = 0; x < 160; x++)
                        image.getPixelWriter().setArgb(x, y, 0xff000000 | decoded.getRGB(x, y));
                    oledFrames.add(image);
                }
            }
        }
        oledPreviewImage.setImage(oledFrames.isEmpty() ? null : oledFrames.get(oledFrame % oledFrames.size()));
        oledPreviewImage.setVisible(!oledFrames.isEmpty());
        oledTitle.setText(resource.deviceKnown() && resource.device().valid() ? "设备已有" : "");
        oledTitle.setVisible(oledFrames.isEmpty());
        oledCaption.setVisible(false);
        oledDraftBadge.setVisible(resource.localStatus() == com.example.ahakey.model.OledResourceState.LocalStatus.DRAFT);
    }

    private void refreshToggleThumb() {
        if (toggleThumb == null || deviceStatus == null) {
            return;
        }
        toggleThumb.setTranslateY(deviceStatus.isAutoApproval() ? -13 : 13);
    }

    private void setStableLightPreview() {
        if (lightSeg1 != null) renderLight(new int[8]);
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
    
    private final com.example.ahakey.service.FirmwareLightSimulator lightSimulator =
            new com.example.ahakey.service.FirmwareLightSimulator();

    private void startLightAnimation() {
        if (lightAnimation != null) lightAnimation.stop();
        lightAnimation = new Timeline(new KeyFrame(Duration.millis(50), event -> {
            var display = studioState.displayConfig();
            if (display.devicePreview.get() && System.nanoTime() >= display.previewUntilNanos.get()) {
                display.endPreview();
                display.message.set("设备预览已结束。");
            }
            int effect = display.simulatedEffect.get();
            renderLight(effect < 0 ? new int[8] : lightSimulator.step(effect, display.simulatedBrightness.get()));
            if (++animationFrame % 2 == 0 && !oledFrames.isEmpty()) {
                oledFrame = (oledFrame + 1) % oledFrames.size();
                oledPreviewImage.setImage(oledFrames.get(oledFrame));
            }
        }));
        lightAnimation.setCycleCount(Timeline.INDEFINITE);
        lightAnimation.play();
    }

    private void renderLight(int[] colors) {
        Region[] segments = {lightSeg1, lightSeg2, lightSeg3, lightSeg4, lightSeg5, lightSeg6, lightSeg7, lightSeg8};
        for (int i = 0; i < segments.length; i++)
            if (segments[i] != null) segments[i].setStyle(String.format("-fx-background-color: #%06x; -fx-opacity: 1;", colors[i]));
    }
    
    public void stopAnimation() {
        if (lightAnimation != null) {
            lightAnimation.stop();
        }
    }
}
