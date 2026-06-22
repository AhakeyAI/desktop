import assert from "node:assert/strict";
import { PassThrough } from "node:stream";
import test from "node:test";

import {
  AhaKeyPluginServer,
  JSON_RPC_ERROR,
  JsonRpcError,
} from "../dist/index.js";

function createHarness(definition) {
  const input = new PassThrough();
  const output = new PassThrough();
  const errorOutput = new PassThrough();
  const messages = [];
  const waiters = [];
  let buffer = "";

  output.setEncoding("utf8");
  output.on("data", (chunk) => {
    buffer += chunk;
    for (;;) {
      const newline = buffer.indexOf("\n");
      if (newline === -1) {
        break;
      }
      const line = buffer.slice(0, newline);
      buffer = buffer.slice(newline + 1);
      if (line.length === 0) {
        continue;
      }
      const message = JSON.parse(line);
      const waiter = waiters.shift();
      if (waiter === undefined) {
        messages.push(message);
      } else {
        waiter(message);
      }
    }
  });

  const server = new AhaKeyPluginServer(definition, {
    input,
    output,
    errorOutput,
    defaultCallTimeoutMs: 500,
  }).start();

  return {
    server,
    send(message) {
      input.write(`${JSON.stringify(message)}\n`);
    },
    nextMessage() {
      const message = messages.shift();
      return message === undefined
        ? new Promise((resolve) => waiters.push(resolve))
        : Promise.resolve(message);
    },
    close() {
      server.close();
      input.end();
      output.end();
      errorOutput.end();
    },
  };
}

const initializeParams = {
  host: {
    bundleID: "dev.ahakey.test",
    version: "1.2.3",
    build: "42",
    platform: "macos",
  },
  hostMethods: ["host/getInfo", "host/log", "host/getSwitchState"],
};

test("serves lifecycle and custom plugin methods", async (t) => {
  let shutdownCalled = false;
  let exitCalled = false;
  const harness = createHarness({
    name: "Test Plugin",
    version: "0.1.0",
    methods: {
      "hello/greet": (params) => ({ message: `Hello, ${params.name}!` }),
    },
    onShutdown() {
      shutdownCalled = true;
    },
    onExit() {
      exitCalled = true;
    },
  });
  t.after(() => harness.close());

  harness.send({
    jsonrpc: "2.0",
    id: 1,
    method: "plugin/initialize",
    params: initializeParams,
  });
  assert.deepEqual(await harness.nextMessage(), {
    jsonrpc: "2.0",
    id: 1,
    result: {
      name: "Test Plugin",
      version: "0.1.0",
      methods: ["hello/greet"],
    },
  });

  assert.equal(harness.server.host.supports("host/log"), true);
  assert.equal(harness.server.host.supports("host/openURL"), false);

  harness.send({
    jsonrpc: "2.0",
    id: "greet-1",
    method: "hello/greet",
    params: { name: "AhaKey" },
  });
  assert.deepEqual(await harness.nextMessage(), {
    jsonrpc: "2.0",
    id: "greet-1",
    result: { message: "Hello, AhaKey!" },
  });

  harness.send({ jsonrpc: "2.0", id: 2, method: "plugin/shutdown" });
  assert.deepEqual(await harness.nextMessage(), {
    jsonrpc: "2.0",
    id: 2,
    result: null,
  });
  assert.equal(shutdownCalled, true);

  harness.send({ jsonrpc: "2.0", method: "plugin/exit" });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(exitCalled, true);
});

test("calls host methods and exposes JSON-RPC errors", async (t) => {
  const harness = createHarness({ name: "Test Plugin", version: "0.1.0" });
  t.after(() => harness.close());

  harness.send({
    jsonrpc: "2.0",
    id: 1,
    method: "plugin/initialize",
    params: initializeParams,
  });
  await harness.nextMessage();

  const infoPromise = harness.server.host.getInfo();
  const request = await harness.nextMessage();
  assert.deepEqual(request, {
    jsonrpc: "2.0",
    id: 1,
    method: "host/getInfo",
  });
  harness.send({
    jsonrpc: "2.0",
    id: request.id,
    result: initializeParams.host,
  });
  assert.deepEqual(await infoPromise, initializeParams.host);

  const rejected = harness.server.host.call("host/blocked");
  const blockedRequest = await harness.nextMessage();
  harness.send({
    jsonrpc: "2.0",
    id: blockedRequest.id,
    error: {
      code: JSON_RPC_ERROR.methodNotFound,
      message: "Method host/blocked not in plugin permissions",
    },
  });
  await assert.rejects(rejected, (error) => {
    assert.ok(error instanceof JsonRpcError);
    assert.equal(error.code, JSON_RPC_ERROR.methodNotFound);
    return true;
  });
});

