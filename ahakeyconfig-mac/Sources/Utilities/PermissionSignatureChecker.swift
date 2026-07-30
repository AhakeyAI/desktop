import Foundation

/// 检测应用签名变化并处理权限问题
/// 
/// 当应用签名改变时（如重新安装、更换证书），macOS 会将其视为新应用，
/// 但旧的 TCC 授权记录仍然存在。由于麦克风权限在系统设置中没有手动添加的 '+' 号，
/// 用户无法手动添加新签名的应用。
/// 
/// 此工具检测签名变化，并提供重置麦克风权限的功能。
enum PermissionSignatureChecker {
    
    private static let lastSignatureKey = "AhaKey_LastSignatureHash"
    
    /// 获取当前应用的签名哈希
    private static func currentSignatureHash() -> String? {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", "--verbose=4", bundlePath]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // 提取签名信息（cdhash）
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    if let range = line.range(of: "cdhash=") {
                        let hash = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                        return hash
                    }
                }
            }
        } catch {
            print("Error getting signature: \(error)")
        }
        return nil
    }
    
    /// 检查签名是否发生变化
    static func hasSignatureChanged() -> Bool {
        guard let current = currentSignatureHash() else { return false }
        let last = UserDefaults.standard.string(forKey: lastSignatureKey)
        return last != current
    }
    
    /// 保存当前签名
    static func saveCurrentSignature() {
        if let current = currentSignatureHash() {
            UserDefaults.standard.set(current, forKey: lastSignatureKey)
        }
    }
    
    /// 重置麦克风权限（需要 sudo）
    /// - Parameter completion: (success, message)
    static func resetMicrophonePermission(completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let bundleId = Bundle.main.bundleIdentifier ?? "lab.jawa.ahakeyconfig"
            
            print("[PermissionSignatureChecker] 开始重置麦克风权限, bundleId: \(bundleId)")
            
            // 先尝试普通模式重置
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", "Microphone", bundleId]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                print("[PermissionSignatureChecker] 普通模式 tccutil 返回: \(task.terminationStatus), 输出: \(output)")
                
                if task.terminationStatus == 0 {
                    completion(true, "麦克风权限已重置")
                    return
                }
                
                // 如果普通模式失败，尝试用 sudo
                let sudoTask = Process()
                sudoTask.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                sudoTask.arguments = ["/usr/bin/tccutil", "reset", "Microphone", bundleId]
                
                let sudoPipe = Pipe()
                sudoTask.standardOutput = sudoPipe
                sudoTask.standardError = sudoPipe
                
                do {
                    try sudoTask.run()
                    sudoTask.waitUntilExit()
                    
                    let sudoData = sudoPipe.fileHandleForReading.readDataToEndOfFile()
                    let sudoOutput = String(data: sudoData, encoding: .utf8) ?? ""
                    
                    print("[PermissionSignatureChecker] sudo 模式 tccutil 返回: \(sudoTask.terminationStatus), 输出: \(sudoOutput)")
                    
                    if sudoTask.terminationStatus == 0 {
                        completion(true, "麦克风权限已重置（使用 sudo）")
                    } else {
                        completion(false, "重置失败:\n普通模式: \(output)\nsudo模式: \(sudoOutput)")
                    }
                } catch {
                    print("[PermissionSignatureChecker] sudo 执行失败: \(error)")
                    completion(false, "sudo 执行失败: \(error.localizedDescription)")
                }
            } catch {
                print("[PermissionSignatureChecker] 执行失败: \(error)")
                completion(false, "执行失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 检查并处理签名变化
    /// - Returns: true 如果签名变化且需要处理
    static func checkAndHandleSignatureChange() -> Bool {
        if hasSignatureChanged() {
            saveCurrentSignature()
            return true
        }
        return false
    }
    
    /// 检查签名变化并自动重置麦克风权限
    static func checkAndResetOnSignatureChange(completion: @escaping (Bool) -> Void) {
        if hasSignatureChanged() {
            saveCurrentSignature()
            resetMicrophonePermission { success, _ in
                completion(success)
            }
        } else {
            completion(false)
        }
    }
}