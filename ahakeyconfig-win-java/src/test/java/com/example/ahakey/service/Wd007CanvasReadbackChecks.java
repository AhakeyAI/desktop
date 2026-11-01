package com.example.ahakey.service;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.model.*;
import com.example.ahakey.view.*;
import javafx.application.Platform;
import javafx.scene.*;
import javafx.scene.control.Label;
import javafx.scene.layout.HBox;
import java.nio.file.Files;
import java.util.*;
import static com.example.ahakey.service.Wd007BehaviorChecks.*;
import static com.example.ahakey.service.Wd007RecoveryControllerChecks.fx;

/** Actual controller readback and FXML canvas, with only the physical USB replaced. */
public final class Wd007CanvasReadbackChecks {
    static List<String> captions(CanvasPane canvas) {
        return java.util.stream.IntStream.rangeClosed(1,4)
                .mapToObj(i -> ((Label)canvas.lookup("#key"+i+"Caption")).getText()).toList();
    }
    public static void main(String[] args) throws Exception {
        System.setProperty("user.home",Files.createTempDirectory("wd007-canvas-").toString());
        Platform.startup(()->{});Platform.setImplicitExit(false);Wire[] wires=new Wire[1];
        StudioController c=fx(()->new StudioController(cb->wires[0]=new Wire(cb),ble->new KimiAhaKeyBridge(ble,0),false));
        try {
            CanvasPane canvas=fx(()->new CanvasPane(c));
            fx(()->{new Scene(new HBox(canvas,new InspectorPane(c))).getRoot().applyCss();c.getStudioState().setSelectedPart(StudioPart.KEY2);return null;});
            Wire wire=wires[0];wire.readbackHid=7;Wd007UsbTerminationChecks.connected(c,wire);
            fx(()->{
                var state=c.getStudioState();
                var expected=List.of(StudioPart.KEY1,StudioPart.KEY2,StudioPart.KEY3,StudioPart.KEY4).stream()
                        .map(k->state.getKeyConfig(k).getDescription()).toList();
                System.out.println("readback captions expected="+expected+" actual="+captions(canvas));
                check(state.getKeyConfig(StudioPart.KEY2).getHidCode()==7,"real readback reached state");
                check(expected.equals(captions(canvas)),"canvas must refresh all four captions without editing or switching selection");
                check(state.getDirtyCount()==0,"readback must not mark drafts dirty");
                int revision=state.revisionProperty().get();
                state.applyOrdinaryKeyReadback(new com.example.ahakey.protocol.AhaKeyResponseParser.OrdinaryKeyReadback(0,1,0x73,new byte[]{7},"updated"));
                check(captions(canvas).get(1).equals("updated"),"later authoritative description refreshes canvas");
                check(state.revisionProperty().get()==revision&&state.getDirtyCount()==0,"baseline refresh leaves draft revision unchanged");
                return null;
            });
            System.out.println("PASS actual FXML canvas follows authoritative readback; no native devices or shown window");
        } finally {fx(()->{c.shutdown();return null;});Platform.exit();}
    }
}
