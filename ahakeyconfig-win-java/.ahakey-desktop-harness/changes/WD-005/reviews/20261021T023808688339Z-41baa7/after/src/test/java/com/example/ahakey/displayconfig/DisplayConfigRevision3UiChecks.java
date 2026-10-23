package com.example.ahakey.displayconfig;

import com.example.ahakey.model.AiRuntimeDisplayMode;
import com.example.ahakey.view.InspectorPane;
import javafx.application.Platform;
import javafx.beans.property.*;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.layout.*;
import javafx.scene.paint.Color;
import java.nio.file.*;
import java.util.concurrent.*;

/** Isolated real CSS and binding helper, not the complete Inspector or application. */
public final class DisplayConfigRevision3UiChecks {
    private static int checks;
    public static void main(String[] args) throws Exception {
        if (args.length != 1) throw new IllegalArgumentException("screenshot output path required");
        Platform.startup(() -> {});
        try {
            FutureTask<Void> task = new FutureTask<>(() -> { verify(Path.of(args[0])); return null; });
            Platform.runLater(task); task.get(30,TimeUnit.SECONDS);
            System.out.println("PASS " + checks + " isolated UI checks; full Inspector/Owner Preview not executed");
        } finally { Platform.exit(); }
    }
    private static void verify(Path imagePath) throws Exception {
        VBox root = new VBox(12); root.setStyle("-fx-padding:20; -fx-background-color:white;");
        root.getChildren().add(new Label("OLED 资源：正常与上传禁用状态"));
        for (String name : new String[]{"Mode 2 · 默认屏幕", "Mode 2 · SINGLE working", "全局 MULTI running"}) {
            HBox row = new HBox(12);
            for (boolean disabled : new boolean[]{false,true}) {
                VBox card = new VBox(4,new Label(name),new Label("草稿"),new Label(name.contains("默认") ? "1 / 8 帧" : "1 / 12 帧"),new Button("更换文件"));
                card.setPrefWidth(350); card.getStyleClass().add("oled-resource"); card.setDisable(disabled);
                row.getChildren().add(card);
            }
            root.getChildren().add(row);
        }
        ObjectProperty<AiRuntimeDisplayMode> mode = new SimpleObjectProperty<>(AiRuntimeDisplayMode.SINGLE);
        BooleanProperty busy = new SimpleBooleanProperty(), pending = new SimpleBooleanProperty();
        TextField draft = new TextField("未保存草稿");
        VBox single = new VBox(4,new Label("SINGLE 当前模式灯效"),draft);
        VBox multi = new VBox(4,new Label("MULTI 主显示：槽位 4"),new Button("管理关注任务槽"));
        var bind = InspectorPane.class.getDeclaredMethod("bindRuntimeSection",VBox.class,ObjectProperty.class,
                AiRuntimeDisplayMode.class,BooleanProperty.class,BooleanProperty.class); bind.setAccessible(true);
        bind.invoke(null,single,mode,AiRuntimeDisplayMode.SINGLE,busy,pending);
        bind.invoke(null,multi,mode,AiRuntimeDisplayMode.MULTI,busy,pending);
        HBox sections = new HBox(12,single,multi); single.setPrefWidth(350); multi.setPrefWidth(350);
        root.getChildren().add(sections);
        new Scene(root,760,640).getStylesheets().add(InspectorPane.class.getResource("/style.css").toExternalForm());
        root.applyCss(); root.layout();
        check("UI03-single-edit-multi-disabled",!single.isDisabled() && multi.isDisabled());
        mode.set(AiRuntimeDisplayMode.MULTI);
        check("UI03-multi-edit-single-disabled",single.isDisabled() && !multi.isDisabled());
        busy.set(true); check("UI03-upload-lock-both",single.isDisabled() && multi.isDisabled());
        busy.set(false); pending.set(true); check("UI03-mode-ACK-lock-both",single.isDisabled() && multi.isDisabled());
        pending.set(false); mode.set(AiRuntimeDisplayMode.SINGLE);
        check("UI03-return-preserves-draft",draft.getText().equals("未保存草稿") && !single.isDisabled());
        root.applyCss(); root.layout();
        for (var node : root.lookupAll(".oled-resource")) {
            VBox card = (VBox)node; Color background = (Color)card.getBackground().getFills().get(0).getFill();
            for (var labelNode : card.lookupAll(".label")) {
                Label label = (Label)labelNode;
                double ratio = contrast((Color)label.getTextFill(),background);
                check("UI01-contrast-"+card.isDisabled()+"-"+label.getText()+"-"+String.format(java.util.Locale.ROOT,"%.2f",ratio),ratio>=4.5 && label.getOpacity()==1 && card.getOpacity()==1);
                check("UI01-visible-"+label.getText(),label.getWidth()>0 && label.getHeight()>0
                        && label.getBoundsInParent().getMaxX()<=card.getWidth());
            }
        }
        Color multiBackground = (Color)multi.getBackground().getFills().get(0).getFill();
        Label multiLabel=(Label)multi.getChildren().get(0);
        check("UI03-disabled-label-readable",contrast((Color)multiLabel.getTextFill(),multiBackground)>=4.5 && multiLabel.getOpacity()==1);
        var image = root.snapshot(null,null);
        var buffered = new java.awt.image.BufferedImage((int)image.getWidth(),(int)image.getHeight(),java.awt.image.BufferedImage.TYPE_INT_ARGB);
        for(int y=0;y<buffered.getHeight();y++) for(int x=0;x<buffered.getWidth();x++) buffered.setRGB(x,y,image.getPixelReader().getArgb(x,y));
        javax.imageio.ImageIO.write(buffered,"png",imagePath.toFile());
    }
    private static double component(double c) { return c<=0.04045 ? c/12.92 : Math.pow((c+0.055)/1.055,2.4); }
    private static double luminance(Color c) { return .2126*component(c.getRed())+.7152*component(c.getGreen())+.0722*component(c.getBlue()); }
    private static double contrast(Color a,Color b) { double x=luminance(a),y=luminance(b); return (Math.max(x,y)+.05)/(Math.min(x,y)+.05); }
    private static void check(String id,boolean ok) { if(!ok) throw new AssertionError(id); checks++; System.out.println("PASS "+id); }
}
