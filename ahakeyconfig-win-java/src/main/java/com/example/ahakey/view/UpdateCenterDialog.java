package com.example.ahakey.view;

import com.example.ahakey.update.*;
import com.example.ahakey.firmware.*;
import com.example.ahakey.util.LanguageManager;
import javafx.animation.*;
import javafx.geometry.Insets;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.layout.*;
import javafx.stage.*;
import javafx.util.Duration;
import java.nio.file.Path;

/** Presentation only. All file/network/device/process work is performed by services. */
public final class UpdateCenterDialog {
    private final UpdateCenterService service;
    private final Stage stage=new Stage();
    private final Timeline refresh;
    private final Label softwareStatus=new Label(), firmwareStatus=new Label(), selected=new Label();
    private final Label installationResult=new Label();
    private final ProgressBar progress=new ProgressBar(0);
    private final Button check,download,cancel,install,local,detect,driver,flash,reconnect,release;

    private final CheckBox risk;


    private FirmwareCatalog.Target lastTarget;
    private String riskTargetHash = "";
    private final boolean english;
    private final TabPane tabs;
    private boolean closePending;
    private Alert closeNotice;
    public UpdateCenterDialog(Window owner,UpdateCenterService service) {
        this.service=service;english="en".equals(LanguageManager.getInstance().getCurrentLanguage());
        if(owner!=null)stage.initOwner(owner);stage.setTitle(t("更新中心","Update Center"));
        check=button("检查更新","Check for updates",service::check);
        download=button("下载新版","Download update",service::downloadSoftware);
        cancel=button("取消下载","Cancel download",service::cancelDownload);
        install=button("退出并安装","Exit and install",()->{if(confirm(t("校验已完成。确认退出本应用并启动安装？安装结果需重启核对。","The package has been verified. Exit this app and start installation? Success is confirmed only after restart.")))service.installConfirmed();});
        softwareStatus.setWrapText(true);progress.setMaxWidth(Double.MAX_VALUE);
        installationResult.setWrapText(true);
        String variant=service.app().variant().equals("local-model")?t("本地模型版","Local model"):t("轻量版","Lite");
        VBox software=new VBox(14,new Label(t("当前安装：","Installed: ")+service.app().version()+" / "+variant),softwareStatus,installationResult,progress,new HBox(10,check,download,cancel,install));software.setPadding(new Insets(20));
        local=button("选择 HEX","Select HEX",()->{
            FileChooser chooser=new FileChooser();chooser.setTitle(t("选择固件 HEX","Choose firmware HEX"));chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter("Intel HEX","*.hex"));
            var file=chooser.showOpenDialog(stage);if(file!=null)service.chooseLocal(file.toPath());
        });
        risk=new CheckBox(t("我确认清除键盘固件与设备配置；本地 HEX 或降级可能不兼容。","I confirm firmware and device settings erasure; a local HEX or downgrade may be incompatible."));risk.setWrapText(true);
        risk.setOnAction(e->{var target=service.selectedFirmware();riskTargetHash=risk.isSelected()&&target!=null?target.hash():"";refresh();});
        detect=button("检测下载设备","Detect boot device",()->{var target=service.selectedFirmware();service.detectSimpleFirmware(risk.isSelected()&&target!=null&&target.hash().equals(riskTargetHash));});
        driver=button("准备驱动","Prepare driver",()->service.firmwareAction(()->service.firmware().prepareDriver()));
        flash=button("开始烧录","Flash",()->service.firmwareAction(()->service.firmware().flashSimple()));
        reconnect=button("检查正常重连","Check reconnect",()->service.firmwareAction(()->service.firmware().checkSimpleReconnect()));
        release=button("退出本次链路","Exit this attempt",service::exitFirmware);
        selected.setWrapText(true);firmwareStatus.setWrapText(true);
        Label instructions=new Label(t("拔掉 USB，将键盘关机；在关机状态按住最左侧语音键；保持按住，将 USB 插入电脑；点击检测下载设备。","Unplug USB and power off the keyboard. While powered off, hold the leftmost voice key. Keep holding it and connect USB to the computer, then click Detect download device."));instructions.setWrapText(true);
        VBox firmware=new VBox(12,local,selected,instructions,risk,new FlowPane(10,10,detect,driver,flash,reconnect,release),firmwareStatus);
        firmware.setPadding(new Insets(20));ScrollPane scroll=new ScrollPane(firmware);scroll.setFitToWidth(true);
        tabs=new TabPane(new Tab(t("软件更新","Software update"),software),new Tab(t("键盘固件","Keyboard firmware"),scroll));tabs.setTabClosingPolicy(TabPane.TabClosingPolicy.UNAVAILABLE);tabs.getSelectionModel().select(0);
        stage.setScene(new Scene(tabs,900,660));stage.setMinWidth(760);stage.setMinHeight(520);
        refresh=new Timeline(new KeyFrame(Duration.millis(200),e->refresh()));refresh.setCycleCount(Animation.INDEFINITE);
        stage.setOnCloseRequest(e->{e.consume();if(closePending)return;closePending=true;service.prepareWindowClose(allowed->javafx.application.Platform.runLater(()->{
            closePending=false;
            if(allowed && service.windowCloseReady())stage.hide();
            else {
                if(closeNotice!=null && closeNotice.isShowing())return;
                closeNotice=new Alert(Alert.AlertType.INFORMATION,t("更新或设备操作尚未结束，或工具清理状态未确认。请待工具结束后退出本次链路。","An update or device operation is still active, or cleanup is not confirmed. Exit this attempt after the tool has ended."));
                closeNotice.initOwner(stage);closeNotice.setHeaderText(null);closeNotice.show();
            }
        }));});
        stage.iconifiedProperty().addListener((o,a,b)->{if(b&&service.firmware().simpleActive())stage.setIconified(false);});
        stage.setOnHidden(e->refresh.stop());refresh();
    }
    public void show(){stage.show();stage.toFront();refresh.play();}
    public TabPane content(){return tabs;}
    public Stage stage(){return stage;}
    private String t(String zh,String en){return english?en:zh;}
    private Button button(String zh,String en,Runnable action){Button b=new Button(t(zh,en));b.setOnAction(e->action.run());return b;}
    private boolean confirm(String message){Alert a=new Alert(Alert.AlertType.CONFIRMATION,message,ButtonType.OK,ButtonType.CANCEL);a.initOwner(stage);a.setHeaderText(null);return a.showAndWait().orElse(ButtonType.CANCEL)==ButtonType.OK;}
    private void refresh(){
        var v=service.view();boolean busy=service.busy();
        softwareStatus.setText(t("状态：","Status: ")+softwareText(v.state())+(v.version().isBlank()?"":" / "+v.version())+"\n"+(english?englishDetail(v.state()):v.detail()));
        String receipt=service.installationResult();
        installationResult.setText(english?receipt.replace("重启已确认：","Restart confirmed: ").replace("上次安装结果：","Previous installation: ").replace("；尚未确认目标版本重启。","; a restart into the target version has not been confirmed.").replace("；目标应用版本已匹配，尚未核实 Windows 系统重启。","; target application matches, but a Windows system restart has not been verified."):receipt);
        installationResult.setVisible(!receipt.isBlank());installationResult.setManaged(!receipt.isBlank());
        progress.setProgress(v.total()>0?(double)v.received()/v.total():v.state()==UpdateCenterService.State.DOWNLOADING?-1:0);
        check.setDisable(busy);download.setDisable(busy||v.state()!=UpdateCenterService.State.AVAILABLE);cancel.setDisable(!service.downloading());install.setDisable(busy||v.state()!=UpdateCenterService.State.READY);
        var f=service.firmware().view();var target=service.selectedFirmware();
        if(target!=lastTarget){risk.setSelected(false);riskTargetHash="";lastTarget=target;}
        selected.setText(target==null?t("请选择固件 HEX。","Select a firmware HEX."):(target.unknownLocal()?t("目标版本未知","Target version unknown"):target.catalog())+"\n"+target.file().getFileName());
        String phase=firmwareText(f.state()), detail=english?"":f.detail();
        firmwareStatus.setText((detail.startsWith(phase)?detail:phase+(detail.isBlank()?"":"\n"+detail))+(service.firmwareError().isBlank()?"":"\n"+t(service.firmwareError(),"This attempt failed. Exit and begin again.")));
        boolean active=service.firmware().simpleActive();
        local.setDisable(busy||active);risk.setDisable(busy||active);
        visible(detect,!active||f.state()==FirmwareUpdateService.State.WAIT_BOOT);visible(driver,f.state()==FirmwareUpdateService.State.DRIVER_NEEDED||f.state()==FirmwareUpdateService.State.DRIVER_PREPARING);
        visible(flash,f.state()==FirmwareUpdateService.State.READY_TO_FLASH||f.state()==FirmwareUpdateService.State.FLASHING||f.state()==FirmwareUpdateService.State.VERIFYING);visible(reconnect,f.state()==FirmwareUpdateService.State.WAIT_RECONNECT);visible(release,active);
        detect.setDisable(busy||target==null||!risk.isSelected()||(active&&f.state()!=FirmwareUpdateService.State.WAIT_BOOT));driver.setDisable(busy||f.state()!=FirmwareUpdateService.State.DRIVER_NEEDED);
        flash.setDisable(busy||f.state()!=FirmwareUpdateService.State.READY_TO_FLASH);reconnect.setDisable(busy||f.state()!=FirmwareUpdateService.State.WAIT_RECONNECT);
        release.setDisable(!active);if(!busy)service.expireFirmware();
    }
    private static void visible(javafx.scene.Node node,boolean visible){node.setVisible(visible);node.setManaged(visible);}
    private String softwareText(UpdateCenterService.State s){return t(switch(s){case UNAVAILABLE->"更新信息不可用";case NO_VARIANT->"未发布匹配形态";case CURRENT->"已是最新版";case AVAILABLE->"有新版可用";case DOWNLOADING->"下载中";case READY->"等待安装确认";case FAILED->"校验或操作失败";case CANCELLED->"已取消";case INSTALLING->"安装协调中";case INSTALL_UNCONFIRMED->"安装待确认";case RESTART_CONFIRMED->"重启已确认";case CHECKING->"检查中";default->"等待检查";},s.name().replace('_',' '));}
    private String englishDetail(UpdateCenterService.State s){return switch(s){case UNAVAILABLE->"Release information is unavailable or unpublished. This does not mean the installed version is current.";case FAILED->"Validation failed. The release signature and actual installer identity must match.";case READY->"Package validated. Installation requires your confirmation.";case INSTALL_UNCONFIRMED->"Installation has not yet been confirmed by a matching application restart.";default->"";};}
    private String firmwareText(FirmwareUpdateService.State s){return t(switch(s){
        case IDLE->"请选择 HEX";case WAIT_BOOT->"等待下载设备";case DRIVER_NEEDED->"下载设备需要驱动";case DRIVER_PREPARING->"驱动准备中";case READY_TO_FLASH->"可以开始烧录";
        case FLASHING->"写入中，请勿拔线";case VERIFYING->"校验中，请勿拔线";case WAIT_RECONNECT->"等待正常重连读取版本";case COMPLETE->"烧录完成";case FAILED,UNCERTAIN->"本次链路失败，点击退出重新链路";default->"准备中";
    },switch(s){
        case IDLE->"Select a HEX";case WAIT_BOOT->"Power off. Hold the leftmost voice key while inserting USB, then detect the device.";
        case DRIVER_NEEDED->"Prepare the bundled driver; Windows permission is required.";case DRIVER_PREPARING->"Preparing driver";case READY_TO_FLASH->"Ready to flash";
        case FLASHING,VERIFYING->"Writing or verifying. Keep USB connected.";case WAIT_RECONNECT->"Unplug USB, release the key, reconnect normally, then check the actual version.";
        case COMPLETE->service.firmware().view().detail().replace("烧录成功，当前版本 ","Flash complete. Actual version: ");case FAILED,UNCERTAIN->"This attempt failed. Exit and begin again.";default->"Preparing";
    });}
}
