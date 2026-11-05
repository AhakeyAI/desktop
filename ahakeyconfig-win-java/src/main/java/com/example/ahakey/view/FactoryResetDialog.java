package com.example.ahakey.view;

import com.example.ahakey.service.FactoryResetService;
import com.example.ahakey.model.FactoryResetState;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.layout.VBox;
import javafx.stage.*;

/** Hiding this window never cancels the service or a firmware operation. */
public final class FactoryResetDialog {
    private final Stage stage=new Stage();
    private final FactoryResetService service;
    private final Label detail=new Label();
    private final Button query=new Button("重新查询"),retry=new Button("重新恢复");
    public FactoryResetDialog(Window owner,FactoryResetService service){
        this.service=service;if(owner!=null)stage.initOwner(owner);stage.setTitle("恢复出厂设置 · 进度");
        Label target=new Label();target.textProperty().bind(service.state().target);target.setWrapText(true);
        detail.textProperty().bind(service.state().message);detail.setWrapText(true);
        query.setOnAction(e->query());retry.setOnAction(e->prepare());
        Button close=new Button("关闭窗口");close.setOnAction(e->stage.hide());
        VBox content=new VBox(14,target,detail,query,retry,new Label("关闭窗口不会停止设备恢复。"),close);content.setPadding(new Insets(20));stage.setScene(new Scene(content,600,340));
        query.disableProperty().bind(service.state().busy);retry.disableProperty().bind(service.state().busy);
        service.state().phase.addListener((o,a,b)->update());service.state().pending.addListener((o,a,b)->update());update();
    }
    public void show(){stage.show();stage.toFront();if(!service.hasPending()&&!service.state().busy.get())prepare();}
    private void update(){
        var phase=service.state().phase.get();query.setVisible(service.hasPending());query.setManaged(query.isVisible());
        query.setText(service.requiresLocalCleanup()?"重试本地清理":phase==FactoryResetState.Phase.READ_FAILED?"重新读取配置":"重新查询");
        retry.setVisible(phase==FactoryResetState.Phase.INCOMPLETE);retry.setManaged(retry.isVisible());
    }
    private void prepare(){
        service.prepare().whenComplete((confirmation,error)->Platform.runLater(()->{
            if(error!=null){alert("无法准备恢复",error);return;}
            Alert dialog=new Alert(Alert.AlertType.CONFIRMATION);dialog.initOwner(stage);dialog.setTitle("确认恢复出厂设置");
            dialog.setHeaderText("目标键盘："+confirmation.target().display());
            dialog.setContentText("所有模式按键、宏、拨杆、语音、待机、灯光和显示将恢复出厂设置；自定义图片/GIF不再使用。\n蓝牙配对、设备名称、固件版本及电脑云端账号保留。\n未保存的设备配置也将丢弃，不会先保存旧草稿。\n请保持 USB 外部供电（可充电线供电 + BLE）。开始后不可撤销，关闭窗口不会停止恢复。");
            ButtonType accept=new ButtonType("确认恢复出厂设置",ButtonBar.ButtonData.OK_DONE);dialog.getButtonTypes().setAll(ButtonType.CANCEL,accept);
            ((Button)dialog.getDialogPane().lookupButton(accept)).setDefaultButton(false);((Button)dialog.getDialogPane().lookupButton(ButtonType.CANCEL)).setDefaultButton(true);
            if(dialog.showAndWait().orElse(ButtonType.CANCEL)==accept)service.confirm(confirmation).exceptionally(failure->{Platform.runLater(()->alert("恢复结果",failure));return null;});
            else service.cancelConfirmation();
        }));
    }
    private void query(){
        FactoryResetService.Association association=null;
        if(!service.requiresLocalCleanup()&&service.definitelyDifferent()){alert("不能关联另一台设备",new IllegalStateException("当前设备与原目标明确不同，不能继续此恢复任务"));return;}
        if(!service.requiresLocalCleanup()&&service.requiresAssociation()){
            Alert dialog=new Alert(Alert.AlertType.CONFIRMATION);dialog.initOwner(stage);dialog.setTitle("核对原设备");dialog.setHeaderText("请确认连接的是上次恢复的键盘");
            association=service.association();
            var old=service.originalTarget();var current=association==null?null:association.target();
            dialog.setContentText("上次目标："+(old==null?"未知":old.display())+"\n当前设备："+(current==null?"未连接":current.display())+"\nUSB 无硬件序列号，不能自动证明同一设备。人工确认仅允许只读查询，仍须匹配恢复次数，不会再次恢复。");
            ButtonType confirm=new ButtonType("确认这是原设备并查询",ButtonBar.ButtonData.OK_DONE);dialog.getButtonTypes().setAll(ButtonType.CANCEL,confirm);
            ((Button)dialog.getDialogPane().lookupButton(confirm)).setDefaultButton(false);((Button)dialog.getDialogPane().lookupButton(ButtonType.CANCEL)).setDefaultButton(true);
            if(dialog.showAndWait().orElse(ButtonType.CANCEL)!=confirm||association==null)return;
        }
        service.queryAgain(association).exceptionally(error->{Platform.runLater(()->alert("查询未完成",error));return null;});
    }
    private void alert(String title,Throwable error){while(error.getCause()!=null)error=error.getCause();Alert alert=new Alert(Alert.AlertType.INFORMATION,error.getMessage(),ButtonType.OK);alert.initOwner(stage);alert.setTitle(title);alert.setHeaderText(title);alert.show();}
}
