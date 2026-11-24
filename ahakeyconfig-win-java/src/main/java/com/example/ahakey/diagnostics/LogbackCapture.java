package com.example.ahakey.diagnostics;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.LoggerContext;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.classic.spi.IThrowableProxy;
import ch.qos.logback.core.AppenderBase;
import org.slf4j.LoggerFactory;

import java.time.Instant;

/** Copies the app's log lines into {@link ConnectionLog} unchanged. */
final class LogbackCapture extends AppenderBase<ILoggingEvent> {
    private LogbackCapture() {}

    static void install() {
        if (!(LoggerFactory.getILoggerFactory() instanceof LoggerContext context)) return;
        LogbackCapture appender = new LogbackCapture();
        appender.setContext(context);
        appender.setName("CONNECTION_LOG");
        appender.start();
        // com.example.ahakey has additivity=false, so attach to it as well as root.
        for (String name : new String[] {Logger.ROOT_LOGGER_NAME, "com.example.ahakey"}) {
            context.getLogger(name).addAppender(appender);
        }
    }

    @Override
    protected void append(ILoggingEvent event) {
        String message = event.getFormattedMessage() == null ? "" : event.getFormattedMessage();
        IThrowableProxy error = event.getThrowableProxy();
        if (error != null) message += " (" + error.getClassName() + ": " + error.getMessage() + ")";
        ConnectionLog.get().add(new ConnectionLog.Entry(Instant.ofEpochMilli(event.getTimeStamp()),
            ConnectionLog.Source.APP, level(event.getLevel()), shortName(event.getLoggerName()),
            message, null));
    }

    static ConnectionLog.Level level(ch.qos.logback.classic.Level level) {
        return switch (level.toInt()) {
            case ch.qos.logback.classic.Level.ERROR_INT -> ConnectionLog.Level.ERROR;
            case ch.qos.logback.classic.Level.WARN_INT -> ConnectionLog.Level.WARN;
            case ch.qos.logback.classic.Level.INFO_INT -> ConnectionLog.Level.INFO;
            default -> ConnectionLog.Level.DEBUG;
        };
    }

    static String shortName(String logger) {
        if (logger == null) return "";
        return logger.substring(logger.lastIndexOf('.') + 1);
    }
}
