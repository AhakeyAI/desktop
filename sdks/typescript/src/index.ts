import { createInterface, type Interface } from "node:readline";
import type { Readable, Writable } from "node:stream";

export type JsonPrimitive = boolean | number | string | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonRpcId = number | string | null;
export type MaybePromise<T> = T | Promise<T>;

export const JSON_RPC_VERSION = "2.0" as const;

export const JSON_RPC_ERROR = {
  parseError: -32700,
  invalidRequest: -32600,
  methodNotFound: -32601,
  invalidParams: -32602,
  internalError: -32603,
} as const;

export class JsonRpcError extends Error {
  readonly code: number;
  readonly data?: unknown;

  constructor(code: number, message: string, data?: unknown) {
    super(message);
    this.name = "JsonRpcError";
    this.code = code;
    this.data = data;
  }

  toJSON(): { code: number; message: string; data?: unknown } {
    return this.data === undefined
      ? { code: this.code, message: this.message }
      : { code: this.code, message: this.message, data: this.data };
  }
}

export interface HostAppInfo {
  bundleID: string;
  version: string;
  build: string;
  platform: string;
}

export interface PluginInitializeParams {
  host: HostAppInfo;
  hostMethods: string[];
}

export interface PluginInitializeResult {
  name?: string;
  version?: string;
  methods?: string[];
}

export interface SwitchStateResult {
  switchState: number | null;
  agentReachable: boolean;
}

export type HostLogLevel = "debug" | "info" | "warn" | "error" | (string & {});

export type RpcMethod<TParams = unknown, TResult = unknown> = (
  params: TParams,
) => MaybePromise<TResult>;

export type RpcNotification<TParams = unknown> = (
  params: TParams,
) => MaybePromise<void>;

export interface PluginContext {
  host: AhaKeyHost;
  initializeParams: PluginInitializeParams;
}

export interface PluginDefinition {
  name: string;
  version: string;
  methods?: Record<string, RpcMethod>;
  notifications?: Record<string, RpcNotification>;
  onInitialize?: (
    params: PluginInitializeParams,
    host: AhaKeyHost,
  ) => MaybePromise<void | Partial<PluginInitializeResult>>;
  onInitialized?: (context: PluginContext) => MaybePromise<void>;
  onShutdown?: (context: PluginContext | undefined) => MaybePromise<void>;
  onExit?: (context: PluginContext | undefined) => MaybePromise<void>;
}

export interface PluginServerOptions {
  input?: Readable;
  output?: Writable;
  errorOutput?: Writable;
  defaultCallTimeoutMs?: number;
}

interface JsonRpcRequest {
  jsonrpc: typeof JSON_RPC_VERSION;
  method: string;
  params?: unknown;
  id?: JsonRpcId;
}

interface JsonRpcResponse {
  jsonrpc: typeof JSON_RPC_VERSION;
  id: JsonRpcId;
  result?: unknown;
  error?: {
    code: number;
    message: string;
    data?: unknown;
  };
}

interface PendingCall {
  resolve: (result: unknown) => void;
  reject: (error: Error) => void;
  timeout: ReturnType<typeof setTimeout> | undefined;
}

function hasOwn(value: object, key: PropertyKey): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asRpcId(value: unknown): JsonRpcId | undefined {
  if (value === null || typeof value === "string" || typeof value === "number") {
    return value;
  }
  return undefined;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

class JsonRpcPeer {
  private readonly input: Readable;
  private readonly output: Writable;
  private readonly errorOutput: Writable;
  private readonly defaultCallTimeoutMs: number;
  private readonly methods = new Map<string, RpcMethod>();
  private readonly notifications = new Map<string, RpcNotification>();
  private readonly pending = new Map<number, PendingCall>();
  private reader: Interface | undefined;
  private nextId = 1;
  private started = false;
  private closed = false;

  constructor(options: PluginServerOptions = {}) {
    this.input = options.input ?? process.stdin;
    this.output = options.output ?? process.stdout;
    this.errorOutput = options.errorOutput ?? process.stderr;
    this.defaultCallTimeoutMs = options.defaultCallTimeoutMs ?? 30_000;
  }

  start(): void {
    if (this.started) {
      return;
    }
    if (this.closed) {
      throw new Error("Cannot restart a closed JSON-RPC peer");
    }

    this.started = true;
    this.reader = createInterface({
      input: this.input,
      crlfDelay: Infinity,
      terminal: false,
    });
    this.reader.on("line", (line) => {
      void this.handleLine(line);
    });
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    this.reader?.close();
    this.input.pause();

    for (const [id, pending] of this.pending) {
      if (pending.timeout !== undefined) {
        clearTimeout(pending.timeout);
      }
      pending.reject(new Error(`JSON-RPC peer closed while waiting for response ${id}`));
    }
    this.pending.clear();
  }

  registerMethod(method: string, handler: RpcMethod): void {
    this.methods.set(method, handler);
  }

  registerNotification(method: string, handler: RpcNotification): void {
    this.notifications.set(method, handler);
  }

  call<TResult = unknown, TParams = unknown>(
    method: string,
    params?: TParams,
    timeoutMs = this.defaultCallTimeoutMs,
  ): Promise<TResult> {
    if (!this.started || this.closed) {
      return Promise.reject(new Error("JSON-RPC peer is not running"));
    }

    const id = this.nextId++;
    const request: JsonRpcRequest = { jsonrpc: JSON_RPC_VERSION, method, id };
    if (params !== undefined) {
      request.params = params;
    }

    return new Promise<TResult>((resolve, reject) => {
      const timeout = timeoutMs > 0
        ? setTimeout(() => {
            this.pending.delete(id);
            reject(new Error(`JSON-RPC call timed out: ${method}`));
          }, timeoutMs)
        : undefined;
      timeout?.unref();

      this.pending.set(id, {
        resolve: (result) => resolve(result as TResult),
        reject,
        timeout,
      });

      try {
        this.send(request);
      } catch (error) {
        this.pending.delete(id);
        if (timeout !== undefined) {
          clearTimeout(timeout);
        }
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }

  notify<TParams = unknown>(method: string, params?: TParams): void {
    if (!this.started || this.closed) {
      throw new Error("JSON-RPC peer is not running");
    }

    const request: JsonRpcRequest = { jsonrpc: JSON_RPC_VERSION, method };
    if (params !== undefined) {
      request.params = params;
    }
    this.send(request);
  }

  logError(message: string): void {
    this.errorOutput.write(`[ahakey-plugin-sdk] ${message}\n`);
  }

  private send(message: JsonRpcRequest | JsonRpcResponse): void {
    this.output.write(`${JSON.stringify(message)}\n`);
  }

  private async handleLine(line: string): Promise<void> {
    const trimmed = line.trim();
    if (trimmed.length === 0) {
      return;
    }

    let message: unknown;
    try {
      message = JSON.parse(trimmed);
    } catch (error) {
      this.sendError(null, new JsonRpcError(
        JSON_RPC_ERROR.parseError,
        `Parse error: ${errorMessage(error)}`,
      ));
      return;
    }

    if (!isRecord(message) || message.jsonrpc !== JSON_RPC_VERSION) {
      this.sendError(null, new JsonRpcError(
        JSON_RPC_ERROR.invalidRequest,
        "Invalid JSON-RPC request",
      ));
      return;
    }

    if (typeof message.method === "string") {
      await this.handleRequest(message);
      return;
    }

    this.handleResponse(message);
  }

  private async handleRequest(message: Record<string, unknown>): Promise<void> {
    const method = message.method as string;
    const params = message.params;
    const isNotification = !hasOwn(message, "id");

    if (isNotification) {
      const handler = this.notifications.get(method);
      if (handler !== undefined) {
        try {
          await handler(params);
        } catch (error) {
          this.logError(`notification ${method} failed: ${errorMessage(error)}`);
        }
      }
      return;
    }

    const id = asRpcId(message.id);
    if (id === undefined) {
      this.sendError(null, new JsonRpcError(
        JSON_RPC_ERROR.invalidRequest,
        "JSON-RPC request id must be a number, string, or null",
      ));
      return;
    }

    const handler = this.methods.get(method);
    if (handler === undefined) {
      this.sendError(id, new JsonRpcError(
        JSON_RPC_ERROR.methodNotFound,
        `Method not found: ${method}`,
      ));
      return;
    }

    try {
      const result = await handler(params);
      this.send({ jsonrpc: JSON_RPC_VERSION, id, result: result ?? null });
    } catch (error) {
      this.sendError(
        id,
        error instanceof JsonRpcError
          ? error
          : new JsonRpcError(JSON_RPC_ERROR.internalError, errorMessage(error)),
      );
    }
  }

  private handleResponse(message: Record<string, unknown>): void {
    const id = asRpcId(message.id);
    if (typeof id !== "number") {
      this.logError("ignoring response with an unknown id");
      return;
    }

    const pending = this.pending.get(id);
    if (pending === undefined) {
      this.logError(`ignoring response for unknown id ${id}`);
      return;
    }
    this.pending.delete(id);
    if (pending.timeout !== undefined) {
      clearTimeout(pending.timeout);
    }

    if (isRecord(message.error)
      && typeof message.error.code === "number"
      && typeof message.error.message === "string") {
      pending.reject(new JsonRpcError(
        message.error.code,
        message.error.message,
        message.error.data,
      ));
      return;
    }
    pending.resolve(message.result ?? null);
  }

  private sendError(id: JsonRpcId, error: JsonRpcError): void {
    this.send({
      jsonrpc: JSON_RPC_VERSION,
      id,
      error: error.toJSON(),
    });
  }
}

export class AhaKeyHost {
  private initializeParams: PluginInitializeParams | undefined;

  constructor(private readonly peer: JsonRpcPeer) {}

  setInitializeParams(params: PluginInitializeParams): void {
    this.initializeParams = params;
  }

  supports(method: string): boolean {
    return this.initializeParams?.hostMethods.includes(method) ?? false;
  }

  call<TResult = unknown, TParams = unknown>(
    method: string,
    params?: TParams,
    timeoutMs?: number,
  ): Promise<TResult> {
    return this.peer.call<TResult, TParams>(method, params, timeoutMs);
  }

  notify<TParams = unknown>(method: string, params?: TParams): void {
    this.peer.notify(method, params);
  }

  getInfo(): Promise<HostAppInfo> {
    return this.call<HostAppInfo>("host/getInfo");
  }

  async log(message: string, level: HostLogLevel = "info"): Promise<void> {
    await this.call("host/log", { level, message });
  }

  getSwitchState(): Promise<SwitchStateResult> {
    return this.call<SwitchStateResult>("host/getSwitchState");
  }
}

export class AhaKeyPluginServer {
  readonly host: AhaKeyHost;

  private readonly peer: JsonRpcPeer;
  private contextValue: PluginContext | undefined;

  constructor(
    private readonly definition: PluginDefinition,
    options: PluginServerOptions = {},
  ) {
    this.peer = new JsonRpcPeer(options);
    this.host = new AhaKeyHost(this.peer);
    this.registerLifecycle();

    for (const [method, handler] of Object.entries(definition.methods ?? {})) {
      this.peer.registerMethod(method, handler);
    }
    for (const [method, handler] of Object.entries(definition.notifications ?? {})) {
      this.peer.registerNotification(method, handler);
    }
  }

  get context(): PluginContext | undefined {
    return this.contextValue;
  }

  start(): this {
    this.peer.start();
    return this;
  }

  close(): void {
    this.peer.close();
  }

  private registerLifecycle(): void {
    this.peer.registerMethod("plugin/initialize", async (params) => {
      if (!isRecord(params)
        || !isRecord(params.host)
        || !Array.isArray(params.hostMethods)
        || !params.hostMethods.every((method) => typeof method === "string")) {
        throw new JsonRpcError(
          JSON_RPC_ERROR.invalidParams,
          "plugin/initialize expects { host, hostMethods }",
        );
      }

      const initializeParams = params as unknown as PluginInitializeParams;
      this.host.setInitializeParams(initializeParams);
      this.contextValue = { host: this.host, initializeParams };
      const overrides = await this.definition.onInitialize?.(initializeParams, this.host);

      return {
        name: this.definition.name,
        version: this.definition.version,
        methods: Object.keys(this.definition.methods ?? {}),
        ...overrides,
      } satisfies PluginInitializeResult;
    });

    this.peer.registerNotification("plugin/initialized", async () => {
      if (this.contextValue !== undefined) {
        await this.definition.onInitialized?.(this.contextValue);
      }
    });

    this.peer.registerMethod("plugin/shutdown", async () => {
      await this.definition.onShutdown?.(this.contextValue);
      return null;
    });

    this.peer.registerNotification("plugin/exit", async () => {
      try {
        await this.definition.onExit?.(this.contextValue);
      } finally {
        this.close();
      }
    });
  }
}

export function definePlugin(definition: PluginDefinition): PluginDefinition {
  return definition;
}

export function servePlugin(
  definition: PluginDefinition,
  options?: PluginServerOptions,
): AhaKeyPluginServer {
  return new AhaKeyPluginServer(definition, options).start();
}

