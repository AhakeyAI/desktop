import SwiftUI
import UniformTypeIdentifiers

struct OLEDManagerView: View {
    @ObservedObject var bleManager: AhaKeyBLEManager

    @State private var selectedImage: NSImage?
    @State private var selectedGIFURL: URL?
    @State private var fps: Int = 30
    @State private var frameCount: Int = 0

    var body: some View {
        Form {
            Section("动画管理") {
                // 预览区
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 160)

                    if let image = selectedImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 140)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                            Text("无图片")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button("添加图片") {
                        selectImage()
                    }
                    .buttonStyle(.bordered)

                    Button("添加 GIF") {
                        selectGIF()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("清空") {
                        selectedImage = nil
                        selectedGIFURL = nil
                        frameCount = 0
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                if frameCount > 0 {
                    HStack {
                        Text("FPS:")
                        Stepper("\(fps)", value: $fps, in: 1...30)
                            .frame(width: 100)
                        Spacer()
                        Text("\(frameCount) 帧")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if bleManager.isConnected {
                Section {
                    Button("上传到设备") {
                        // TODO: 通过 BLE 0x7343 分包上传图片/GIF 数据
                        // OLED 分辨率和图片格式待逆向确认
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedImage == nil && selectedGIFURL == nil)
                }
            } else {
                Section {
                    Text("请先连接 AhaKey 设备")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func selectImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .bmp]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            selectedImage = NSImage(contentsOf: url)
            selectedGIFURL = nil
            frameCount = 0
        }
    }

    private func selectGIF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gif")!]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try OLEDFrameEncoder.validateGIFSourceFileSize(at: url)
            } catch {
                NSSound.beep()
                return
            }
            selectedGIFURL = url
            selectedImage = NSImage(contentsOf: url)
            // GIF 帧数估算
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                frameCount = CGImageSourceGetCount(source)
            }
        }
    }
}
