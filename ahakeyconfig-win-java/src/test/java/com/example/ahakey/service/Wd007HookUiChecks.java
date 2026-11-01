package com.example.ahakey.service;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.view.TopBar;
import javafx.application.Platform;
import javafx.scene.*;
import javafx.scene.control.*;
import javafx.scene.layout.VBox;
import javafx.stage.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import static com.example.ahakey.service.Wd007BehaviorChecks.*;
import static com.example.ahakey.service.Wd007RecoveryControllerChecks.fx;

/** Actual management window, scans and asynchronous button handlers, isolated installer home. */
public final class Wd007HookUiChecks {
    static List<Node> nodes(Node node){var result=new ArrayList<Node>();result.add(node);if(node instanceof ScrollPane s)result.addAll(nodes(s.getContent()));else if(node instanceof Parent p)for(Node child:p.getChildrenUnmodifiable())result.addAll(nodes(child));return result;}
    static void until(Callable<Boolean> condition,String message)throws Exception {
        long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(8);
        while(System.nanoTime()<end){if(fx(condition)){check(true,message);return;}Thread.sleep(20);}throw new AssertionError(message);
    }
    static VBox card(Stage dialog,String platform){return (VBox)nodes(dialog.getScene().getRoot()).stream().filter(n->n instanceof VBox box&&box.getStyleClass().contains("dialog-card")&&nodes(box).stream().anyMatch(c->c instanceof Label l&&l.getText().equals(platform))).findFirst().orElseThrow();}
    static boolean label(VBox card,String text){return nodes(card).stream().anyMatch(n->n instanceof Label l&&l.getText().contains(text));}
    static Button action(VBox card){return (Button)nodes(card).stream().filter(n->n instanceof Button).findFirst().orElseThrow();}
    public static void main(String[] args)throws Exception {
        Path home=Files.createTempDirectory("wd007-hook-ui-");System.setProperty("user.home",home.toString());
        Platform.startup(()->{});Platform.setImplicitExit(false);
        var installer=new Wd007HookManagementChecks.Installed();
        StudioController c=fx(()->new StudioController(Wire::new,ble->new KimiAhaKeyBridge(ble,0),false));
        try {
            TopBar bar=fx(()->new TopBar(c,c.getDeviceStatus(),c.getStudioState(),c.getAgentManager()));
            var field=TopBar.class.getDeclaredField("hookInstaller");field.setAccessible(true);field.set(bar,installer);
            Stage parent=fx(()->{Stage s=new Stage();s.setScene(new Scene(bar));s.show();return s;});
            var open=TopBar.class.getDeclaredMethod("showHookManagerDialog");open.setAccessible(true);
            for(int round=0;round<2;round++) {
                Stage dialog=fx(()->{open.invoke(bar);return (Stage)Window.getWindows().stream().filter(w->w!=parent&&w.isShowing()).findFirst().orElseThrow();});
                until(()->!label(card(dialog,"Claude"),"检测中"),"scan completes");
                check(fx(()->Window.getWindows().stream().filter(Window::isShowing).count()==2),"opening manager never creates modal update prompt");
                if(round==0)for(String platform:List.of("Claude","Kimi")) {
                    fx(()->{Button button=action(card(dialog,platform));check(!button.isDisabled(),"explicit install enabled");button.fire();return null;});
                    until(()->label(card(dialog,platform),"最新")&&label(card(dialog,platform),"成功："),"actual button finishes with persistent success and latest "+platform);
                    check(installer.getHookStatus(platform)==HookInstaller.HookStatus.LATEST,"UI success matches real registration");
                }
                else check(fx(()->label(card(dialog,"Claude"),"最新")&&label(card(dialog,"Kimi"),"最新")),"reopen remains latest");
                fx(()->{dialog.close();return null;});
            }
            Path broken=installer.getHookConfigPath("Claude");Files.writeString(broken,"{}");
            Stage dialog=fx(()->{open.invoke(bar);return (Stage)Window.getWindows().stream().filter(w->w!=parent&&w.isShowing()).findFirst().orElseThrow();});
            until(()->!action(card(dialog,"Claude")).isDisabled(),"update available for missing registration");
            Files.writeString(broken,"{malformed");
            fx(()->{action(card(dialog,"Claude")).fire();return null;});
            until(()->label(card(dialog,"Claude"),"未完成："),"actual button reports malformed-config failure inline");
            check(Files.readString(broken).equals("{malformed"),"failed UI operation preserves invalid config");
            check(fx(()->Window.getWindows().stream().filter(Window::isShowing).count()==2),"failure does not leave a hidden modal blocker");
            System.out.println("PASS real Hook window open/reopen, Claude/Kimi buttons, stable scan and visible failure; isolated home only");
        } finally {fx(()->{c.shutdown();for(Window w:List.copyOf(Window.getWindows()))w.hide();return null;});Platform.exit();}
    }
}
