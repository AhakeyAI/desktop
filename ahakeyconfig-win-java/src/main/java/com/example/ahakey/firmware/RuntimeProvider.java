package com.example.ahakey.firmware;

import java.io.IOException;

/** Replaceable runtime boundary for unit tests and release packaging. */
@FunctionalInterface
public interface RuntimeProvider extends RuntimeLocator {
    @Override
    RuntimeBundle resolve() throws IOException;
}
