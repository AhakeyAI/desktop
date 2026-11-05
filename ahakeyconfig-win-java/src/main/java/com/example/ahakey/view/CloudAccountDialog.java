package com.example.ahakey.view;

import com.example.ahakey.service.*;
import com.google.zxing.BarcodeFormat;
import com.google.zxing.qrcode.QRCodeWriter;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.image.*;
import javafx.scene.layout.*;
import javafx.stage.*;
import java.util.concurrent.*;
import java.util.function.Supplier;

/** One account window and one durable-in-memory redemption surface per application. */
public final class CloudAccountDialog implements AutoCloseable {
    private final Stage stage=new Stage();
    private final CloudAccountManager account;
    private final AhaTypeService aha;
    private final Runnable changed;
    private final VBox content=new VBox(10);
    private final Label status=new Label();
    private final ExecutorService worker=Executors.newCachedThreadPool(r->{Thread t=new Thread(r,"cloud-account-ui");t.setDaemon(true);return t;});
    private TextField phone;
    private PasswordField password;
    private CheckBox remember;
    private boolean busy;
    private long paymentWindow;
    private Stage paymentStage,redeemStage;
    private AhaTypeService.Session redeemSession;
    private boolean closed;
    public CloudAccountDialog(Window owner,Runnable changed){this(owner,CloudAccountManager.getInstance(),changed);}
    public CloudAccountDialog(Window owner,CloudAccountManager account,Runnable changed){
        this.account=account;this.aha=account.ahaType();this.changed=changed;
        if(owner!=null)stage.initOwner(owner);stage.setTitle("云端账号 · AhaType");
        content.setPadding(new Insets(18));status.setWrapText(true);stage.setScene(new Scene(content,580,410));
        stage.setOnHidden(e->{stopPayment();if(redeemStage!=null)redeemStage.hide();});
        render();
    }
    public void show(){if(!stage.isShowing()&&!busy)render();stage.show();stage.toFront();}
    private void render(){
        content.getChildren().clear();
        content.getChildren().add(new Label("AhaType 云端账号"));
        if(!account.isLoggedIn()){
            phone=new TextField(aha.getRememberedPhone());phone.setPromptText("手机号");
            password=new PasswordField();password.setPromptText("密码");password.setText(aha.getRememberedPassword());
            remember=new CheckBox("记住密码");remember.setSelected(aha.isRememberPassword());
            remember.setOnAction(e->{if(!remember.isSelected())try{aha.remember(phone.getText(),"",false);}catch(Exception failure){remember.setSelected(true);status.setText("删除保存密码失败，请检查存储权限");}});
            Button login=new Button("登录"),register=new Button("注册");
            login.setOnAction(e->authenticate(false));register.setOnAction(e->authenticate(true));
            content.getChildren().addAll(phone,password,remember,new HBox(8,login,register));
        }else{
            content.getChildren().addAll(new Label("当前账号："+account.accountName()),new Label("服务有效期："+known(aha.getTokenValidUntil())),new Label(aha.getStatusMessage()));
            var quota=aha.getQuota();var policy=aha.getPolicy();
            for(String p:new String[]{"daily","weekly","monthly"}){
                if(Boolean.FALSE.equals(policy.get("enable_"+p)))continue;
                content.getChildren().add(new Label((p.equals("daily")?"日":p.equals("weekly")?"周":"月")+"额度："+known(quota.get("used_"+p))+" / "+known(quota.get("limit_"+p))));
            }
            Button refresh=new Button("刷新账号"),pay=new Button("微信充值"),coupon=new Button("兑换码"),logout=new Button("退出登录");
            refresh.setOnAction(e->{var session=aha.session();run("正在刷新账号…",()->account.refreshProfile(session),true);});
            pay.setOnAction(e->choosePlan());coupon.setOnAction(e->redeem());
            logout.setOnAction(e->{stopPayment();if(redeemStage!=null){redeemStage.close();redeemStage=null;}run("正在退出…",account::logout,true);});
            content.getChildren().add(new HBox(8,refresh,pay,coupon,logout));
        }
        status.setText(account.status());content.getChildren().add(status);
    }
    private static String known(Object v){return v==null||v.toString().isBlank()?"未获取":v.toString();}
    private void authenticate(boolean register){
        String p=phone.getText(),secret=password.getText();boolean save=remember.isSelected();
        run(register?"注册中…":"登录中…",()->account.authenticate(p,secret,save,register),true);
    }
    private void run(String message,Supplier<String> operation,boolean renderSuccess){
        if(busy||closed)return;boolean wasLoggedIn=account.isLoggedIn();busy=true;content.setDisable(true);status.setText(message);
        worker.execute(()->{
            String result;try{result=operation.get();}catch(Exception failure){result="请求失败，请检查网络与本地存储";}
            String messageResult=result;
            Platform.runLater(()->{if(closed)return;busy=false;content.setDisable(false);if(renderSuccess&&(messageResult==null||account.isLoggedIn()||wasLoggedIn!=account.isLoggedIn()))render();status.setText(messageResult==null?account.status():messageResult);changed.run();});
        });
    }
    private void redeem(){
        var session=aha.session();
        if(redeemStage!=null&&redeemSession!=null&&aha.current(redeemSession)){redeemStage.show();redeemStage.toFront();return;}
        if(redeemStage!=null)redeemStage.close();
        redeemSession=session;redeemStage=new Stage();redeemStage.initOwner(stage);redeemStage.setTitle("兑换码");
        Stage window=redeemStage;TextField code=new TextField();code.setPromptText("兑换码");Label message=new Label("兑换将计入当前账号");message.setWrapText(true);
        Button cancel=new Button("取消"),submit=new Button("确认兑换"),next=new Button("兑换新码");cancel.setOnAction(e->window.hide());
        next.setVisible(false);next.setManaged(false);
        next.setOnAction(e->{
            if(!aha.current(session)||!account.isLoggedIn()){message.setText("请重新登录后打开新的兑换窗口");return;}
            code.clear();code.setDisable(false);submit.setDisable(false);next.setVisible(false);next.setManaged(false);
            message.setText("新兑换将计入当前账号；请输入新码并确认");code.requestFocus();
        });
        submit.setOnAction(e->{
            if(!aha.current(session)){message.setText("账号已变化，请重新打开兑换窗口");return;}
            String value=code.getText();if(value.isBlank()){message.setText("请输入兑换码");return;}
            submit.setDisable(true);code.setDisable(true);message.setText("正在兑换…");
            worker.execute(()->{var outcome=account.redeemResult(value,session);Platform.runLater(()->{
                if(closed||window!=redeemStage)return;
                account.deliverOperation(outcome,current->{
                    message.setText(current.message());code.setDisable(current.success()||current.unknown());
                    submit.setDisable(current.success()||current.unknown()||!account.isLoggedIn());
                    next.setVisible(current.success());next.setManaged(current.success());next.setDisable(!account.isLoggedIn());
                    if(!account.isLoggedIn()){render();status.setText(current.message());}
                    changed.run();
                });
            });});
        });
        VBox box=new VBox(10,new Label("当前账号："+account.accountName()),message,code,new HBox(8,cancel,submit,next));box.setPadding(new Insets(18));window.setScene(new Scene(box,440,220));window.show();
    }
    private void choosePlan(){
        var plans=account.plans();if(plans.isEmpty()){status.setText("未获取有效价格，当前无可用套餐，请刷新账号");return;}
        var confirmedSession=aha.session();
        var choice=new ChoiceDialog<>(plans.get(0),plans);choice.initOwner(stage);choice.setTitle("微信充值");choice.setHeaderText("当前账号："+account.accountName()+"；请选择套餐并确认建单");
        choice.showAndWait().ifPresent(plan->{
            if(busy)return;long ticket=++paymentWindow;var session=confirmedSession;busy=true;content.setDisable(true);status.setText("正在创建订单…");
            worker.execute(()->{
                CloudAccountManager.Order order=null;String error=null;
                try{order=account.createOrder(plan,session);}catch(Exception e){error=e instanceof AhaTypeService.CloudFailure?e.getMessage():"建单结果未确认或响应无效；未自动重复建单";}
                var result=order;String failure=error;
                Platform.runLater(()->{if(closed)return;busy=false;content.setDisable(false);if(ticket!=paymentWindow||!stage.isShowing()||!aha.current(session))return;
                    if(failure!=null){status.setText(failure);return;}showPayment(result,ticket);
                });
            });
        });
    }
    private void showPayment(CloudAccountManager.Order order,long ticket){
        try{
            var bits=new QRCodeWriter().encode(order.url(),BarcodeFormat.QR_CODE,280,280);WritableImage image=new WritableImage(280,280);
            for(int y=0;y<280;y++)for(int x=0;x<280;x++)image.getPixelWriter().setArgb(x,y,bits.get(x,y)?0xff000000:0xffffffff);
            if(paymentStage!=null)paymentStage.close();paymentStage=new Stage();Stage window=paymentStage;window.initOwner(stage);window.setTitle("微信扫码支付");
            Label message=new Label("正在查询付款结果…");message.setWrapText(true);Button close=new Button("关闭");close.setOnAction(e->window.close());
            VBox box=new VBox(10,new Label(String.format(java.util.Locale.ROOT,"金额：%.2f 元%s",order.amountFen()/100.0,order.quotedAmount()?"（所选套餐报价）":"")),new ImageView(image),message,close);box.setPadding(new Insets(16));
            window.setScene(new Scene(box,350,430));window.setOnHidden(e->{if(ticket==paymentWindow){paymentWindow++;account.cancelPaymentPolling();}});window.show();
            account.startPaymentPollingResult(order,result->Platform.runLater(()->{
                if(closed||ticket!=paymentWindow||!window.isShowing())return;
                account.deliverOperation(result,current->{message.setText(current.message());if(!account.isLoggedIn()){render();status.setText(current.message());}changed.run();});
            }));
        }catch(Exception e){status.setText("二维码生成失败；后端订单未取消，请勿重复付款");}
    }
    private void stopPayment(){paymentWindow++;account.cancelPaymentPolling();if(paymentStage!=null){paymentStage.close();paymentStage=null;}}
    @Override public void close(){closed=true;stopPayment();stage.close();if(redeemStage!=null)redeemStage.close();worker.shutdownNow();}
}
