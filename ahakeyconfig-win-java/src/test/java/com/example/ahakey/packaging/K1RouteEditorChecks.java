package com.example.ahakey.packaging;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.*;
import com.example.ahakey.protocol.*;
import com.example.ahakey.service.*;
import com.example.ahakey.view.InspectorPane;
import javafx.application.Platform;
import javafx.scene.*;
import javafx.scene.control.*;
import java.nio.file.*;
import java.util.*;
import java.util.concurrent.*;
import static com.example.ahakey.update.UpdateCenterChecks.*;

public final class K1RouteEditorChecks {
    static <T>T fx(Callable<T> action)throws Exception {if(Platform.isFxApplicationThread())return action.call();FutureTask<T> task=new FutureTask<>(action);Platform.runLater(task);return task.get(10,TimeUnit.SECONDS);}
    static List<Node> nodes(Node node){List<Node> result=new ArrayList<>();result.add(node);if(node instanceof Parent p)for(Node child:p.getChildrenUnmodifiable())result.addAll(nodes(child));return result;}
    static void idle(StudioController c)throws Exception {long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(15);while(System.nanoTime()<end){if(fx(()->!c.getStudioState().k1Routes().busy.get()&&!c.getStudioState().syncingProperty().get())){fx(()->null);return;}Thread.sleep(20);}throw new AssertionError("K1 operation did not finish: "+fx(()->c.getStudioState().syncStatusProperty().get()));}
    static class Fixture implements AutoCloseable {
        StudioController controller;K1RouteProtocolChecks.Wire wire;InspectorPane pane;javafx.stage.Stage stage;
        Fixture(boolean legacy,boolean missing)throws Exception {
            this(legacy,missing,wire->{});
        }
        Fixture(boolean legacy,boolean missing,java.util.function.Consumer<K1RouteProtocolChecks.Wire> setup)throws Exception {
            controller=fx(()->new StudioController(callback->{try{wire=new K1RouteProtocolChecks.Wire(callback);wire.legacy=legacy;wire.missingBank=missing;setup.accept(wire);return wire;}catch(Exception e){throw new RuntimeException(e);}},KimiAhaKeyBridge::new,false));
            fx(()->{controller.getDeviceStatus().setConnected(true);controller.getAgentManager().setBluetoothOwner(AgentManager.BluetoothOwner.AHAKEY_STUDIO);controller.getStudioState().setSelectedPart(StudioPart.KEY1);pane=new InspectorPane(controller);stage=new javafx.stage.Stage();stage.setScene(new Scene(pane,650,850));stage.show();controller.getK1RouteService().connectionChanged();return null;});idle(controller);
        }
        StudioState state(){return controller.getStudioState();}
        void select(ModeSlot mode,StudioPart part)throws Exception {fx(()->{state().setSelectedMode(mode);state().setSelectedPart(part);return null;});idle(controller);}
        void edit(StudioPart part,int hid)throws Exception {fx(()->{state().getKeyConfig(part).setHidCode(hid);state().markDirty(part);return null;});}
        void save()throws Exception {fx(()->{controller.syncAllModes(false);return null;});idle(controller);}
        public void close()throws Exception {fx(()->{stage.hide();controller.shutdown();return null;});}
    }
    static void connectionOrdering(Fixture f,boolean legacyFirst)throws Exception {
        fx(()->{f.state().k1Routes().reset(f.wire.connectionGeneration());for(ModeSlot mode:ModeSlot.values())f.state().getKeyConfig(mode,StudioPart.KEY1).setHidCode(99);return null;});
        var input=StudioController.class.getDeclaredMethod("startCp4cInputReadback",String.class);input.setAccessible(true);
        var catalog=StudioController.class.getDeclaredMethod("handleFirmwareCatalogKey",BleManager.FirmwareIdentity.class,long.class);catalog.setAccessible(true);
        var handled=StudioController.class.getDeclaredField("handledFirmwareIdentity");handled.setAccessible(true);handled.set(f.controller,null);
        if(legacyFirst){fx(()->{f.controller.getK1RouteService().refresh();return null;});idle(f.controller);}
        f.wire.frames.clear();fx(()->{input.invoke(f.controller,com.example.ahakey.firmware.FirmwareCatalog.CATALOG);return null;});
        long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
        while(System.nanoTime()<end&&(f.wire.frames.stream().filter(b->b[2]==(byte)0x87).count()<16||fx(()->f.state().inputReadbackInProgressProperty().get())))Thread.sleep(20);
        fx(()->null);check("actual connect input reader completed before capability order="+legacyFirst,f.wire.frames.stream().filter(b->b[2]==(byte)0x87).count()>=16);
        if(!legacyFirst)check("old early K1 read cannot authorize unknown capability",fx(()->f.state().getKeyConfig(StudioPart.KEY1).getHidCode()==99));
        fx(()->{catalog.invoke(f.controller,f.wire.firmwareIdentity(),f.wire.connectionGeneration());return null;});fx(()->null);idle(f.controller);
        end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);while(System.nanoTime()<end&&fx(()->f.state().inputReadbackInProgressProperty().get()))Thread.sleep(20);
        for(ModeSlot mode:ModeSlot.values())check("connection handler retains correct K1 in mode "+mode+" order="+legacyFirst,fx(()->f.state().k1Routes().confirmed(mode.getIndex())&&f.state().getKeyConfig(mode,StudioPart.KEY1).getHidCode()==4+mode.getIndex()));
        f.select(ModeSlot.MODE0,StudioPart.KEY2);f.edit(StudioPart.KEY2,30);f.save();
        check("K2 save after connection ordering preserves all K1 values "+legacyFirst,java.util.stream.IntStream.range(0,4).allMatch(m->Arrays.equals(f.wire.actions[m][0],new byte[]{(byte)(4+m)})));
        f.select(ModeSlot.MODE0,StudioPart.KEY1);
    }
    public static void main(String[] args)throws Exception {
        System.setProperty("user.home",Files.createTempDirectory("r9-k1-editor-home-").toString());Platform.startup(()->{});Platform.setImplicitExit(false);
        try {
            try(Fixture f=new Fixture(false,false)) {
                check("actual pane displays read-only Consumer usage",fx(()->nodes(f.pane).stream().anyMatch(n->n instanceof Label l&&l.getText().contains("Consumer usage 0x00E9"))));
                check("route refresh loads actual device description",fx(()->f.state().getKeyConfig(StudioPart.KEY1).getDescription().equals("device-0-0")));
                check("Consumer has no authoring selector",fx(()->nodes(f.pane).stream().filter(n->n instanceof ComboBox<?>).noneMatch(n->((ComboBox<?>)n).getItems().stream().anyMatch(x->x.toString().contains("Consumer")))));
                K1Route[] before=f.wire.routes.clone();f.select(ModeSlot.MODE1,StudioPart.KEY2);f.edit(StudioPart.KEY2,42);f.wire.frames.clear();f.save();
                check("K2-only controller save preserves all Consumer routes",Arrays.equals(before,f.wire.routes)&&f.wire.commits==0);
                check("K2 save never sends legacy K1 action or description",f.wire.frames.stream().noneMatch(b->b[2]==0x73&&b[5]==0));
                f.select(ModeSlot.MODE0,StudioPart.KEY1);
                fx(()->{ComboBox combo=(ComboBox)nodes(f.pane).stream().filter(n->n instanceof ComboBox<?> box&&box.getItems().contains("宏")).findFirst().orElseThrow();combo.setValue("宏");return null;});
                check("real pane action-type change marks exact K1 mode dirty",fx(()->f.state().k1Routes().dirty(0)&&!f.state().k1Routes().dirty(1)));
                fx(()->{f.state().getKeyConfig(StudioPart.KEY1).setDescription("中文 Actual description beyond twenty");return null;});
                f.select(ModeSlot.MODE1,StudioPart.KEY2);f.edit(StudioPart.KEY2,43);f.save();
                check("A K1 plus B K2 commits only A K1",f.wire.commits==1&&!f.wire.routes[0].consumer()&&f.wire.routes[1].equals(before[1]));
                check("K1 description uses existing ASCII truncation semantics",f.wire.descriptions[0][0].equals(DeviceSyncService.sanitizeDescription("中文 Actual description beyond twenty")));
                check("confirmed K1 route save clears matching revision",!fx(()->f.state().k1Routes().dirty(0)));
                f.select(ModeSlot.MODE0,StudioPart.KEY1);fx(()->{f.state().getKeyConfig(StudioPart.KEY1).getMacro().clear();return null;});f.edit(StudioPart.KEY1,0x6d);f.wire.uncertainCommit=true;int commits=f.wire.commits;f.save();
                check("uncertain commit resolved by authority read without replay",f.wire.commits==commits+1&&!fx(()->f.state().k1Routes().dirty(0))&&Arrays.equals(f.wire.routes[0].action(),new byte[]{0x6d}));
                f.edit(StudioPart.KEY1,5);f.wire.onCommit=()->{try{fx(()->{f.state().getKeyConfig(StudioPart.KEY1).setHidCode(6);f.state().markDirty(StudioPart.KEY1);return null;});}catch(Exception e){throw new RuntimeException(e);}};f.save();
                check("edit during route commit retains newer draft",fx(()->f.state().k1Routes().dirty(0)&&f.state().getKeyConfig(StudioPart.KEY1).getHidCode()==6));
                f.wire.onCommit=()->{};
                f.select(ModeSlot.MODE2,StudioPart.KEY1);check("switch-mode loads matching device description",fx(()->f.state().getKeyConfig(StudioPart.KEY1).getDescription().equals("device-2-0")));
            }
            // Use isolated state for each controller so the prior test's intentional newer draft cannot leak.
            System.setProperty("user.home",Files.createTempDirectory("r9-k1-b1-home-").toString());
            try(Fixture f=new Fixture(false,true)) {
                check("B1 capability remains ROUTE but authority is unavailable",fx(()->f.state().k1Routes().capability.get()==K1RouteState.Capability.ROUTE&&!f.state().k1Routes().confirmed(0)));
                check("B1 pane reports unavailable, never invents defaults",fx(()->nodes(f.pane).stream().anyMatch(n->n instanceof Label l&&l.getText().contains("无法确认当前设置"))));
                check("B1 actual key editor disabled",fx(()->nodes(f.pane).stream().filter(n->n instanceof ComboBox<?>).allMatch(Node::isDisabled)));
                f.edit(StudioPart.KEY1,8);f.select(ModeSlot.MODE1,StudioPart.KEY2);f.edit(StudioPart.KEY2,9);f.save();
                check("B1 K2 saves while unconfirmed K1 draft stays dirty",Arrays.equals(f.wire.actions[1][1],new byte[]{9})&&fx(()->f.state().k1Routes().dirty(0))&&f.wire.commits==0);
                check("B1 no old K1 fallback or whole-bank initialization",f.wire.frames.stream().noneMatch(b->b[2]==0x73&&b[5]==0)&&f.wire.begins==0);
            }
            System.setProperty("user.home",Files.createTempDirectory("r9-k1-legacy-home-").toString());
            try(Fixture f=new Fixture(true,false)) {
                connectionOrdering(f,false);connectionOrdering(f,true);
                check("legacy capability triggers actual K1 reread",fx(()->f.state().k1Routes().capability.get()==K1RouteState.Capability.LEGACY&&f.state().getKeyConfig(StudioPart.KEY1).getHidCode()==4));
                for(ModeSlot mode:ModeSlot.values())check("legacy rereads distinct K1 baseline in mode "+mode,fx(()->f.state().getKeyConfig(mode,StudioPart.KEY1).getHidCode()==4+mode.getIndex()&&f.state().k1Routes().confirmed(mode.getIndex())));
                f.select(ModeSlot.MODE0,StudioPart.KEY2);f.edit(StudioPart.KEY2,30);f.save();
                check("K2-only legacy save preserves all four distinct K1 values",java.util.stream.IntStream.range(0,4).allMatch(m->Arrays.equals(f.wire.actions[m][0],new byte[]{(byte)(4+m)})));
                f.select(ModeSlot.MODE0,StudioPart.KEY1);
                f.edit(StudioPart.KEY1,7);f.save();check("legacy success clears exact revision",!fx(()->f.state().k1Routes().dirty(0))&&!fx(()->f.state().isDirty(StudioPart.KEY1)));
                f.edit(StudioPart.KEY1,8);var changed=new java.util.concurrent.atomic.AtomicBoolean();f.wire.onLegacyRead=()->{if(changed.compareAndSet(false,true))try{fx(()->{f.state().getKeyConfig(StudioPart.KEY1).setHidCode(9);f.state().markDirty(StudioPart.KEY1);return null;});}catch(Exception e){throw new RuntimeException(e);}};f.save();
                check("legacy ACK/readback does not clear newer edit",fx(()->f.state().k1Routes().dirty(0)&&f.state().getKeyConfig(StudioPart.KEY1).getHidCode()==9));
                f.wire.onLegacyRead=()->{};
            }
            try(Fixture f=new Fixture(false,false,wire->{byte[] longAction=new byte[98];for(int i=0;i<98;i+=2){longAction[i]=1;longAction[i+1]=4;}wire.routes[0]=K1Route.ordinary(0x74,longAction);wire.actions[0][0]=longAction;wire.types[0][0]=0x74;wire.descriptions[0][0]="long-description";})) {
                check("legal 98-byte route remains authoritative when 0x87 returns TOO_LARGE",fx(()->f.state().k1Routes().confirmed(0)&&!f.state().k1Routes().descriptionKnown(0)&&f.state().getKeyConfig(StudioPart.KEY1).getMacroStepCount()==49));
                check("unreadable description stays disabled while action editor remains available",fx(()->nodes(f.pane).stream().filter(n->n instanceof TextField t&&t.getPromptText().equals(com.example.ahakey.util.LanguageManager.getInstance().getString("inspector.desc-placeholder"))).allMatch(Node::isDisabled)));
                fx(()->{f.state().markDirty(StudioPart.KEY1);return null;});f.wire.frames.clear();f.save();
                check("long route action save confirmed without writing or rereading unchanged description",!fx(()->f.state().k1Routes().dirty(0))&&f.wire.descriptions[0][0].equals("long-description")&&f.wire.frames.stream().noneMatch(b->b[2]==0x87||b[2]==0x73&&b[5]==0));
            }
            try(Fixture f=new Fixture(false,false)) {
                fx(()->{var key=f.state().getKeyConfig(StudioPart.KEY1);key.getMacro().clear();for(int i=0;i<18;i++)key.addMacroStep("DOWN_KEY",4);f.state().markDirty(StudioPart.KEY1);f.state().updateKeyDescription(StudioPart.KEY1,"12345678901234567890");return null;});f.wire.frames.clear();f.save();
                check("36-byte macro plus 20-byte changed description rejected before any route commit",f.wire.begins==0&&f.wire.commits==0&&fx(()->f.state().k1Routes().dirty(0)&&f.state().syncStatusProperty().get().contains("53字节")));
                fx(()->{f.state().updateKeyDescription(StudioPart.KEY1,"12345678901234567");return null;});f.save();
                check("53-byte combined action-description boundary saves and verifies",f.wire.commits==1&&!fx(()->f.state().k1Routes().dirty(0)));
            }
            System.out.println("PASS actual InspectorPane + StudioController + K1RouteService + BleManager memory wire; no hardware writes");
        }finally{Platform.exit();}
    }
}
