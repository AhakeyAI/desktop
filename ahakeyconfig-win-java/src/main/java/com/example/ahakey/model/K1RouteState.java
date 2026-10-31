package com.example.ahakey.model;

import javafx.beans.property.*;

/** FX-thread state; dirty ownership is (mode,K1), never dirtyModes x dirtyParts. */
public final class K1RouteState {
    public enum Capability { UNKNOWN, LEGACY, ROUTE }
    public final ObjectProperty<Capability> capability = new SimpleObjectProperty<>(Capability.UNKNOWN);
    public final IntegerProperty revision = new SimpleIntegerProperty();
    public final BooleanProperty busy = new SimpleBooleanProperty();
    public final StringProperty message = new SimpleStringProperty("K1能力尚未确认");
    private final K1Route[] routes = new K1Route[4];
    private final long[] edits = new long[4];
    private final boolean[] dirty = new boolean[4];
    private final boolean[] confirmed = new boolean[4];
    private final String[] descriptions = new String[4];
    private final boolean[] descriptionEdited = new boolean[4];
    private long generation = -1;
    public long generation() { return generation; }
    public boolean confirmed(int mode) { return confirmed[mode]; }
    public K1Route route(int mode) { return routes[mode]; }
    public boolean dirty(int mode) { return dirty[mode]; }
    public long edit(int mode) { return edits[mode]; }
    public String description(int mode){return descriptions[mode];}
    public boolean descriptionKnown(int mode){return descriptions[mode]!=null;}
    public boolean descriptionEdited(int mode){return descriptionEdited[mode];}
    public void markDescriptionEdited(int mode){descriptionEdited[mode]=true;}
    public void observedDescription(int mode,String description){descriptions[mode]=description;revision.set(revision.get()+1);}
    public void markEdited(int mode) { dirty[mode]=true;edits[mode]++;revision.set(revision.get()+1); }
    public void reset(long next) { generation=next;capability.set(Capability.UNKNOWN);java.util.Arrays.fill(confirmed,false);java.util.Arrays.fill(routes,null);java.util.Arrays.fill(descriptions,null);message.set("K1能力尚未确认");revision.set(revision.get()+1); }
    public void observed(int mode,K1Route route) { routes[mode]=route;confirmed[mode]=true;revision.set(revision.get()+1); }
    public void failed(int mode,String reason) { confirmed[mode]=false;message.set(reason);revision.set(revision.get()+1); }
    public void saved(int mode,long edit,K1Route route) { observed(mode,route);if(edits[mode]==edit){dirty[mode]=false;descriptionEdited[mode]=false;}revision.set(revision.get()+1); }
    public void savedLegacy(int mode,long edit) { if(edits[mode]==edit){dirty[mode]=false;descriptionEdited[mode]=false;}revision.set(revision.get()+1); }
    public void observedLegacy(int mode) {confirmed[mode]=true;revision.set(revision.get()+1);}
}
