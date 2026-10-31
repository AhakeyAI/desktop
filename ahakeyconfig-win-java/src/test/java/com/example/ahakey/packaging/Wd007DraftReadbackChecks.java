package com.example.ahakey.packaging;

import com.example.ahakey.model.*;
import com.example.ahakey.model.connection.DeviceTarget;
import com.example.ahakey.service.*;
import com.example.ahakey.firmware.DeviceMaintenanceChecks;
import javafx.application.Platform;
import javafx.scene.control.ComboBox;
import java.nio.file.Files;
import java.util.concurrent.TimeUnit;
import static com.example.ahakey.packaging.K1RouteEditorChecks.*;
import static com.example.ahakey.update.UpdateCenterChecks.check;

/** Full controller connection/readback and real Inspector selectors, no native devices. */
public final class Wd007DraftReadbackChecks {
    static void connect(Fixture f,String transport,String id,int key)throws Exception{
        idle(f.controller);
        var reset=BleManager.class.getDeclaredMethod("resetDisplaySession");reset.setAccessible(true);reset.invoke(f.wire);
        DeviceMaintenanceChecks.field(f.wire,"activeTarget",new DeviceTarget(transport,id,id));
        f.wire.actions[0][1]=new byte[]{(byte)key};f.wire.frames.clear();
        var cb=BleManager.class.getDeclaredField("callback");cb.setAccessible(true);
        ((BleManager.BleCallback)cb.get(f.wire)).onConnected();
        long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
        while(System.nanoTime()<end){
            if(f.wire.frames.stream().filter(b->b[2]==(byte)0x87).count()>=16&&fx(()->!f.state().inputReadbackInProgressProperty().get()&&f.state().k1Routes().confirmed(0)))break;
            Thread.sleep(10);
        }
        check("actual connection performs all ordinary readbacks "+transport+id,f.wire.frames.stream().filter(b->b[2]==(byte)0x87).count()>=16);
        idle(f.controller);fx(()->null);
    }
    public static void main(String[] args)throws Exception{
        System.setProperty("user.home",Files.createTempDirectory("wd007-controller-").toString());Platform.startup(()->{});Platform.setImplicitExit(false);
        try(Fixture f=new Fixture(true,false)){
            connect(f,"BLE","A",20);f.select(ModeSlot.MODE0,StudioPart.KEY2);f.edit(StudioPart.KEY2,31);
            fx(()->{f.state().updateSideSwitchBinding(0,2);return null;});
            connect(f,"BLE","B",21);
            check("B displays actual readback, no A draft",fx(()->f.state().getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).getHidCode()==21&&!f.state().isDirty(StudioPart.KEY2)));
            connect(f,"BLE","A",22);
            check("reliable BLE A identity retains dirty draft through real readback",fx(()->f.state().getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).getHidCode()==31&&f.state().isDirty(StudioPart.KEY2)));
            check("A side draft remains separate from saved approval facts",fx(()->f.state().getSideSwitchConfig().up().binding()==2&&f.wire.getCachedStatus().getSavedBindings().up().binding()==0&&f.wire.getCachedStatus().isAutoApproval()));
            connect(f,"USB","same-path",24);f.edit(StudioPart.KEY2,44);String original=f.wire.draftIdentity();
            var observed=BleManager.class.getDeclaredMethod("observeUsbCandidates",java.util.Set.class);observed.setAccessible(true);observed.invoke(f.wire,java.util.Set.of());
            // Recreate the memory handle after actual disconnect; same path has no hardware serial.
            DeviceMaintenanceChecks.field(f.wire,"usbTransport",f.wire.usb);f.wire.usb.opened=true;
            DeviceMaintenanceChecks.field(f.wire,"isConnected",true);f.wire.getCachedStatus().setConnected(true);
            connect(f,"USB","same-path",25);
            check("same-path new attachment never imports previous physical keyboard draft",fx(()->!original.equals(f.wire.draftIdentity())&&f.state().getKeyConfig(ModeSlot.MODE0,StudioPart.KEY2).getHidCode()==25&&!f.state().isDirty(StudioPart.KEY2)));
            for(StudioPart part:new StudioPart[]{StudioPart.KEY1,StudioPart.KEY2,StudioPart.KEY3,StudioPart.KEY4}){
                f.select(ModeSlot.MODE0,part);
                fx(()->{
                    var choices=nodes(f.pane).stream().filter(n->n instanceof ComboBox<?> box&&box.getItems().stream().anyMatch(x->x.toString().startsWith("F18"))).map(n->(ComboBox<?>)n).toList();
                    check(part+" shortcut F18 first",!choices.isEmpty()&&choices.stream().allMatch(c->c.getItems().get(0).toString().startsWith("F18")));
                    @SuppressWarnings("unchecked") ComboBox<String> action=(ComboBox<String>)nodes(f.pane).stream().filter(n->n instanceof ComboBox<?> box&&box.getItems().contains("宏")).findFirst().orElseThrow();action.setValue("宏");
                    return null;
                });
                fx(()->{
                    var choices=nodes(f.pane).stream().filter(n->n instanceof ComboBox<?> box&&box.getItems().stream().anyMatch(x->x.toString().startsWith("F18"))).map(n->(ComboBox<?>)n).toList();
                    check(part+" macro F18 first",!choices.isEmpty()&&choices.stream().allMatch(c->c.getItems().get(0).toString().startsWith("F18")));return null;
                });
            }
            System.out.println("PASS controller A-B-A, USB replacement and all four F18 editor paths");
        }finally{Platform.exit();}
    }
}
