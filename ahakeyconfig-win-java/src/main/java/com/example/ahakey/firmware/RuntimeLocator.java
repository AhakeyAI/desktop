package com.example.ahakey.firmware;

import java.io.IOException;

/** Resolves the one WCHISP runtime used by a Studio operation. */
@FunctionalInterface
public interface RuntimeLocator {
    RuntimeBundle resolve() throws IOException;
}
