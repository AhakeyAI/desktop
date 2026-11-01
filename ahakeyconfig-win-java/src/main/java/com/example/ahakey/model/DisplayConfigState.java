package com.example.ahakey.model;

import javafx.beans.property.*;
import javafx.collections.FXCollections;
import javafx.collections.ObservableMap;
import java.util.Arrays;

/** Mutated only on the FX thread; worker results carry a connection/load generation. */
public final class DisplayConfigState {
    public final ObservableMap<Integer, OledResourceState> resources = FXCollections.observableHashMap();
    public final IntegerProperty group = new SimpleIntegerProperty(0);
    public final IntegerProperty substate = new SimpleIntegerProperty(0);
    public final IntegerProperty selectedEntry = new SimpleIntegerProperty(0);
    public final IntegerProperty revision = new SimpleIntegerProperty();
    public final BooleanProperty busy = new SimpleBooleanProperty();
    public final BooleanProperty loading = new SimpleBooleanProperty();
    public final BooleanProperty ready = new SimpleBooleanProperty();
    public final BooleanProperty writeReady = new SimpleBooleanProperty();
    public final BooleanProperty previewReady = new SimpleBooleanProperty();
    public final BooleanProperty runtimeReady = new SimpleBooleanProperty();
    public final StringProperty previewDisabledReasonKey = new SimpleStringProperty("display.identity-disconnected");
    public final StringProperty runtimeDisabledReasonKey = new SimpleStringProperty("display.identity-disconnected");
    public final BooleanProperty capabilityReady = new SimpleBooleanProperty();
    public final StringProperty disabledReasonKey = new SimpleStringProperty("display.identity-disconnected");
    public final StringProperty message = new SimpleStringProperty("");
    public final StringProperty progress = new SimpleStringProperty("");
    public final IntegerProperty brightness = new SimpleIntegerProperty(35);
    public final IntegerProperty simulatedEffect = new SimpleIntegerProperty(-1);
    public final IntegerProperty simulatedBrightness = new SimpleIntegerProperty(35);
    public final LongProperty previewUntilNanos = new SimpleLongProperty();
    public final BooleanProperty devicePreview = new SimpleBooleanProperty();
    private boolean brightnessDirty;
    private boolean brightnessObserved;
    private final boolean[][] effectsObserved=new boolean[4][9];
    public boolean brightnessKnownOrEdited(){return brightnessObserved||brightnessDirty;}
    public boolean effectKnownOrEdited(int mode,int ai){return effectsObserved[mode][ai]||effectDirty[mode][ai];}
    public void invalidateLightingObservations() {
        brightnessObserved=false;if(!brightnessDirty)brightness.set(35);
        for(int mode=0;mode<4;mode++)for(int ai=0;ai<9;ai++){effectsObserved[mode][ai]=false;if(!effectDirty[mode][ai])effects[mode][ai]=-1;}
        endPreview();changed();
    }
    private long brightnessRevision;
    private final long[][] effectRevisions = new long[4][9];
    private boolean previewSimulation;
    private final int[][] effects = new int[4][9];
    private final boolean[][] effectDirty = new boolean[4][9];
    private record LightingDraft(int brightness, boolean brightnessDirty, long brightnessRevision,
                                 int[][] effects, boolean[][] dirty, long[][] revisions) {}
    private final java.util.Map<String,LightingDraft> lightingDrafts=new java.util.HashMap<>();
    private String lightingTarget="";
    /** Only user edits are restored. Clean device observations expire at every target transition. */
    public void selectDevice(String identity) {
        if(identity==null || identity.isBlank() || identity.equals(lightingTarget))return;
        int[][] values=new int[4][];boolean[][] dirty=new boolean[4][];long[][] edits=new long[4][];
        for(int m=0;m<4;m++){values[m]=effects[m].clone();dirty[m]=effectDirty[m].clone();edits[m]=effectRevisions[m].clone();}
        lightingDrafts.put(lightingTarget,new LightingDraft(brightness.get(),brightnessDirty,brightnessRevision,values,dirty,edits));
        LightingDraft draft=lightingDrafts.get(identity);lightingTarget=identity;
        brightnessDirty=draft!=null&&draft.brightnessDirty();brightness.set(brightnessDirty?draft.brightness():35);
        brightnessRevision=draft==null?0:draft.brightnessRevision();
        for(int m=0;m<4;m++)for(int ai=0;ai<9;ai++) {
            effectDirty[m][ai]=draft!=null&&draft.dirty()[m][ai];
            effects[m][ai]=effectDirty[m][ai]?draft.effects()[m][ai]:-1;
            effectRevisions[m][ai]=draft==null?0:draft.revisions()[m][ai];
        }
        invalidateLightingObservations();message.set("已切换配置目标；正在读取当前设备，本地灯光草稿按目标保留。");changed();
    }
    /** Historical local defaults are not user edits or device observations. */
    public void initializeLegacy(int level, int[][] defaults) {
        if(!brightnessDirty)brightness.set(level);
        for(int m=0;m<4;m++)for(int ai=0;ai<9;ai++)if(!effectDirty[m][ai])effects[m][ai]=defaults[m][ai];
        changed();
    }

    public DisplayConfigState() {
        for (int i = 0; i < 19; i++) resources.put(i, OledResourceState.empty(i));
        for (int[] mode : effects) Arrays.fill(mode, -1);
    }
    public void select(int mode, int newGroup, int state) {
        if (busy.get()) return;
        if (mode < 0 || mode > 3 || newGroup < 0 || newGroup > 2 || state < 0 || state > 2)
            throw new IllegalArgumentException("OLED selection");
        group.set(newGroup);
        substate.set(state);
        selectedEntry.set(newGroup == 2 ? 16 + state : mode * 4 + (newGroup == 0 ? 0 : state + 1));
        changed();
    }
    public OledResourceState current() { return resources.get(selectedEntry.get()); }
    public void put(OledResourceState state) { resources.put(state.entry(), state); changed(); }
    public void changed() { revision.set(revision.get() + 1); }
    public void editBrightness(int value) {
        if (value < 1 || value > 100) throw new IllegalArgumentException("brightness");
        brightness.set(value); brightnessDirty = true; brightnessRevision++; simulate(1); changed();
    }
    public void readBrightness(int value) { brightnessObserved=true;if (!brightnessDirty) brightness.set(value); changed(); }
    public void savedBrightness(int value) { if (brightness.get() == value) brightnessDirty = false; endPreview(); changed(); }
    public boolean brightnessDirty() { return brightnessDirty; }
    public long brightnessRevision() { return brightnessRevision; }
    public void savedBrightness(int value, long edit) {
        if (edit == brightnessRevision) savedBrightness(value); else endPreview();
    }
    public int effect(int mode, int ai) { return effects[mode][ai]; }
    public void editEffect(int mode, int ai, int effect) {
        if (effect < 0 || effect > 16) throw new IllegalArgumentException("effect");
        effects[mode][ai] = effect; effectDirty[mode][ai] = true; effectRevisions[mode][ai]++; simulate(effect); changed();
    }
    public void readEffect(int mode, int ai, int effect) { effectsObserved[mode][ai]=true;if (!effectDirty[mode][ai]) effects[mode][ai] = effect; changed(); }
    public void savedEffect(int mode, int ai, int effect) { if (effects[mode][ai] == effect) effectDirty[mode][ai] = false; endPreview(); changed(); }
    public boolean effectDirty(int mode, int ai) { return effectDirty[mode][ai]; }
    public long effectRevision(int mode, int ai) { return effectRevisions[mode][ai]; }
    public void savedEffect(int mode, int ai, int effect, long edit) {
        if (edit == effectRevisions[mode][ai]) savedEffect(mode, ai, effect); else endPreview();
    }
    public void simulate(int effect) {
        simulatedEffect.set(effect); simulatedBrightness.set(brightness.get()); previewSimulation = false; changed();
    }
    public void previewAccepted(int effect, int level) {
        previewAccepted(effect, level, System.nanoTime());
    }
    public void previewAccepted(int effect, int level, long acceptedAt) {
        simulatedEffect.set(effect); simulatedBrightness.set(level); devicePreview.set(true);
        previewSimulation = true;
        previewUntilNanos.set(acceptedAt + 10_000_000_000L); changed();
    }
    public void endPreview() {
        if (previewSimulation) simulatedEffect.set(-1);
        previewSimulation = false;
        devicePreview.set(false); previewUntilNanos.set(0);
    }
}
