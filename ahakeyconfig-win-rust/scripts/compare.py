#!/usr/bin/env python3
"""
Java 版 vs Rust 版 AhaKey Studio 对比测试

测量项:
- 内存占用 (Working Set - MB)
- 启动时间 (ms)
- 进程数
- 进程总占用 (MB)
"""
import subprocess
import time
import sys
import json
import argparse
from pathlib import Path


def run_ps(cmd: str) -> str:
    """执行 PowerShell 命令并返回 stdout"""
    r = subprocess.run(
        ["powershell", "-NoProfile", "-Command", cmd],
        capture_output=True, text=True, encoding="utf-8", errors="ignore"
    )
    return r.stdout.strip()


def measure_process(name_pattern: str, wait_sec: float = 2.0) -> dict:
    """测量匹配 name_pattern 的进程"""
    time.sleep(wait_sec)
    cmd = f"""
    Get-Process | Where-Object {{
        $_.ProcessName -match '{name_pattern}' -or
        $_.MainWindowTitle -match '{name_pattern}'
    }} | Select-Object ProcessName, Id, {{(Get-Process -Id $_.Id -ErrorAction SilentlyContinue).WorkingSet}}, @{{Name='ThreadCount';Expression={{$_.Threads.Count}}}} | ConvertTo-Json -Depth 2
    """
    out = run_ps(cmd)
    if not out:
        return {"processes": [], "total_mb": 0, "count": 0}
    try:
        procs = json.loads(out)
        if isinstance(procs, dict):
            procs = [procs]
    except json.JSONDecodeError:
        return {"processes": [], "total_mb": 0, "count": 0}

    total_mb = sum(p.get("WorkingSet", 0) or 0 for p in procs) / (1024 * 1024)
    return {
        "processes": [{"name": p.get("ProcessName"), "pid": p.get("Id"), "mb": round((p.get("WorkingSet") or 0) / (1024*1024), 1)} for p in procs],
        "total_mb": round(total_mb, 1),
        "count": len(procs),
    }


def measure_startup(exe_path: str) -> dict:
    """测量启动时间"""
    start = time.time()
    proc = subprocess.Popen([exe_path])
    start_time = time.time() - start

    # 等待窗口出现
    for _ in range(50):
        time.sleep(0.1)
        try:
            h = proc._handle
            if h:
                break
        except Exception:
            pass

    boot_time_ms = round((time.time() - start) * 1000, 1)
    return {"boot_time_ms": boot_time_ms, "pid": proc.pid}


def main():
    parser = argparse.ArgumentParser(description="Compare Java vs Rust AhaKey Studio")
    parser.add_argument("--java-name", default="ahakey|AhaKey|java", help="Java 版进程名匹配")
    parser.add_argument("--rust-name", default="AhaKeyStudio|ahakey-studio", help="Rust 版进程名匹配")
    parser.add_argument("--rust-exe", default="", help="Rust exe 路径(可选,自动启动测量)")
    parser.add_argument("--java-exe", default="", help="Java 版启动命令(可选,自动启动测量)")
    args = parser.parse_args()

    print("=" * 60)
    print("AhaKey Studio - Java vs Rust 对比测试")
    print("=" * 60)

    # 测量 Java 版
    print("\n[Java 版运行情况]")
    java = measure_process(args.java_name, wait_sec=3.0)
    print(f"  进程数: {java['count']}")
    print(f"  内存占用: {java['total_mb']} MB")
    for p in java['processes']:
        print(f"    - {p['name']} (PID {p['pid']}): {p['mb']} MB")

    # 测量 Rust 版
    print("\n[Rust 版运行情况]")
    rust = measure_process(args.rust_name, wait_sec=2.0)
    print(f"  进程数: {rust['count']}")
    print(f"  内存占用: {rust['total_mb']} MB")
    for p in rust['processes']:
        print(f"    - {p['name']} (PID {p['pid']}): {p['mb']} MB")

    # 对比
    if java['count'] > 0 and rust['count'] > 0:
        print("\n" + "=" * 60)
        print("对比结果")
        print("=" * 60)
        proc_diff = java['count'] - rust['count']
        mem_diff = java['total_mb'] - rust['total_mb']
        proc_pct = (proc_diff / java['count']) * 100 if java['count'] else 0
        mem_pct = (mem_diff / java['total_mb']) * 100 if java['total_mb'] else 0
        print(f"  进程数: {java['count']} → {rust['count']} (减少 {proc_diff}, {proc_pct:.1f}%)")
        print(f"  内存:   {java['total_mb']} MB → {rust['total_mb']} MB (节省 {mem_diff:.1f} MB, {mem_pct:.1f}%)")
    elif java['count'] == 0 and rust['count'] == 0:
        print("\n[!] 两个版本都未运行,请先启动 Java 版和 Rust 版")
    elif java['count'] == 0:
        print("\n[!] Java 版未运行,只测到 Rust")
    else:
        print("\n[!] Rust 版未运行,只测到 Java")

    print("\n" + "=" * 60)
    print("完成")
    print("=" * 60)


if __name__ == "__main__":
    main()
