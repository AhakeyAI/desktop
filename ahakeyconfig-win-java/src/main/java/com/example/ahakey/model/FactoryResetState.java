package com.example.ahakey.model;

import javafx.beans.property.*;

/** UI projection only. The service owns the operation even when its window is hidden. */
public final class FactoryResetState {
    public enum Phase { IDLE, CHECKING, CONFIRM, WAITING, RESTORING, UNKNOWN, INCOMPLETE, READING, READ_FAILED, COMPLETE, UNAVAILABLE }
    public final ObjectProperty<Phase> phase=new SimpleObjectProperty<>(Phase.IDLE);
    public final StringProperty message=new SimpleStringProperty("");
    public final StringProperty target=new SimpleStringProperty("");
    public final BooleanProperty readOnly=new SimpleBooleanProperty();
    public final BooleanProperty pending=new SimpleBooleanProperty();
    public final BooleanProperty busy=new SimpleBooleanProperty();
}
