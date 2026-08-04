// 全局 UI 状态:toast 通知 + modal 弹窗
import { writable } from "svelte/store";

export interface Toast {
  id: number;
  type: "info" | "success" | "warning" | "error";
  message: string;
  duration: number;
}

export const toasts = writable<Toast[]>([]);

let nextId = 1;

export function toast(message: string, type: Toast["type"] = "info", duration = 3000) {
  const t: Toast = { id: nextId++, type, message, duration };
  toasts.update((list) => [...list, t]);
  setTimeout(() => {
    toasts.update((list) => list.filter((x) => x.id !== t.id));
  }, duration);
}

export const toastInfo = (msg: string) => toast(msg, "info");
export const toastSuccess = (msg: string) => toast(msg, "success");
export const toastWarning = (msg: string) => toast(msg, "warning", 4000);
export const toastError = (msg: string) => toast(msg, "error", 5000);

// Modal 类型
export type ModalType =
  | null
  | "device-info"
  | "version-info"
  | "language"
  | "exit"
  | "restore-defaults"
  | "reconnect"
  | "clear-oled"
  | "about-rust";

export const activeModal = writable<ModalType>(null);
