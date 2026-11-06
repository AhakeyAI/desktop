package com.example.ahakey.view;

import com.example.ahakey.model.OledResourceState.Asset;
import com.example.ahakey.util.OLEDFrameEncoder;
import javafx.animation.KeyFrame;
import javafx.animation.Timeline;
import javafx.scene.control.*;
import javafx.scene.image.Image;
import javafx.scene.image.ImageView;
import javafx.scene.image.WritableImage;
import javafx.scene.layout.VBox;
import javafx.stage.Window;
import javafx.util.Duration;
import java.util.ArrayList;
import java.util.List;

/** Local-only preview. No transport or persistence access exists in this dialog. */
public final class CompactUploadPreviewDialog extends Dialog<Boolean> {
    private final Timeline animation=new Timeline();
    public CompactUploadPreviewDialog(Window owner,String target,Asset asset) {
        if(owner!=null)initOwner(owner);
        setTitle("OLED 上传预览");setHeaderText(target+" · "+asset.modeText());
        ButtonType keep=new ButtonType("使用此预览保存草稿",ButtonBar.ButtonData.OK_DONE);
        getDialogPane().getButtonTypes().addAll(ButtonType.CANCEL,keep);
        ((Button)getDialogPane().lookupButton(keep)).setDefaultButton(false);
        ((Button)getDialogPane().lookupButton(ButtonType.CANCEL)).setDefaultButton(true);
        ImageView view=new ImageView();view.setId("compact-preview-image");view.setFitWidth(480);view.setFitHeight(240);view.setSmooth(false);
        byte[] bytes=asset.bytes();List<Image> images=new ArrayList<>();
        for(int f=0;f<asset.frames();f++) {
            var decoded=OLEDFrameEncoder.decodeFrame(bytes,f*28672);WritableImage image=new WritableImage(160,80);
            for(int y=0;y<80;y++)for(int x=0;x<160;x++)image.getPixelWriter().setArgb(x,y,decoded.getRGB(x,y));
            images.add(image);
        }
        view.setImage(images.get(0));Label frameLabel=new Label("第 1 / "+asset.frames()+" 帧 · "+asset.durationMillis(0)+" ms");frameLabel.setId("compact-preview-timing");
        long total=0;List<String> durations=new ArrayList<>();
        for(int f=0;f<asset.frames();f++) {
            final int frame=f;int ms=asset.durationMillis(f);durations.add(Integer.toString(ms));
            animation.getKeyFrames().add(new KeyFrame(Duration.millis(total),e->{view.setImage(images.get(frame));frameLabel.setText("第 "+(frame+1)+" / "+asset.frames()+" 帧 · "+ms+" ms");}));
            total+=ms;
        }
        animation.getKeyFrames().add(new KeyFrame(Duration.millis(total)));
        animation.setCycleCount(Timeline.INDEFINITE);
        Label details=new Label(asset.frames()+" 帧 · 一轮 "+total+" ms · 上传 "+asset.transferBytes()+" 字节\n每帧时长（ms）："+String.join(" / ",durations));
        details.setWrapText(true);details.setId("compact-preview-details");
        Label note=new Label(asset.compact()?"快速模式：整段动画共用 16 色，80×40 放大到 160×80。上方显示设备实际编码后的像素，颜色与细节会减少。":"原画质模式：160×80 RGB565，沿用兼容上传；动画沿用 100 ms 每帧。");
        note.setWrapText(true);
        Label local=new Label("此窗口只预览，不写入键盘。保存草稿后，需再点击“上传并应用”。");local.setWrapText(true);
        VBox body=new VBox(12,view,frameLabel,details,note,local);body.setPrefWidth(500);
        getDialogPane().setContent(body);
        setResultConverter(button->button==keep);
        setOnShown(e->animation.playFromStart());setOnHidden(e->animation.stop());
    }
    public static ChoiceDialog<String> modeDialog(Window owner) {
        ChoiceDialog<String> dialog=new ChoiceDialog<>("原画质上传","原画质上传","快速上传");
        if(owner!=null)dialog.initOwner(owner);
        dialog.setTitle("选择 OLED 上传方式");dialog.setHeaderText("导入后先预览，确认上传才会写入键盘");
        dialog.setContentText("原画质：现有 RGB565 画质\n快速：16 色、80×40，需支持 ACR3 的固件");
        return dialog;
    }
}
