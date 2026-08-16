package com.example.ahakey;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.platform.windows.WindowsVoiceRelayService;
import com.example.ahakey.platform.windows.WindowsVoiceTyping;
import com.example.ahakey.service.VoiceInputManager;
import com.example.ahakey.util.LanguageManager;
import com.example.ahakey.view.CanvasPane;
import com.example.ahakey.view.InspectorPane;
import com.example.ahakey.view.StatusBar;
import com.example.ahakey.view.TopBar;
import javafx.animation.PauseTransition;
import javafx.util.Duration;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.beans.binding.Bindings;
import javafx.scene.Scene;
import javafx.scene.control.ScrollPane;
import javafx.scene.image.Image;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.stage.Stage;
import javafx.stage.WindowEvent;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.awt.SystemTray;
import java.awt.TrayIcon;
import java.awt.MenuItem;
import java.awt.PopupMenu;
import java.awt.event.ActionListener;
import java.awt.event.MouseAdapter;
import java.awt.event.MouseEvent;
import java.awt.Toolkit;
import java.awt.Font;

/**
 * AhaKey Studio 主应用类
 * 
 * JavaFX 桌面应用的入口，类比于 Java Web 中的 Servlet 或 Spring Boot 的 Application 类。
 * 
 * JavaFX 应用结构说明（类比 Web 开发）：
 * - Stage（舞台）：相当于浏览器窗口，是整个应用的顶层容器
 * - Scene（场景）：相当于 HTML 的 body，包含所有 UI 元素
 * - Pane（面板）：相当于 HTML 的 div，用于布局管理
 * - Node（节点）：相当于 HTML 的各种标签（button、label 等）
 * 
 * 生命周期方法：
 * 1. main() - 程序入口，调用 launch() 启动 JavaFX 运行时
 * 2. init() - 可选，在 start() 之前调用，用于初始化资源（本项目未使用）
 * 3. start() - 核心方法，构建 UI 界面
 * 4. stop() - 可选，应用关闭时调用（本项目通过 setOnCloseRequest 处理）
 */
public class App extends Application {
    
    private static final Logger logger = LoggerFactory.getLogger(App.class);
    
    /**
     * 主控制器，负责协调各个组件之间的通信
     * 类比于 Spring MVC 中的 Controller，管理应用的业务逻辑和状态
     */
    private StudioController controller;
    
    /**
     * 语音输入管理器，负责管理语音识别和键盘注入功能
     */
    private VoiceInputManager voiceInputManager;
    private boolean shuttingDown;
    
    /**
     * 系统托盘图标
     */
    private TrayIcon trayIcon;
    private Stage primaryStage;
    
    /**
     * 保存窗口原始尺寸，用于从托盘恢复时恢复尺寸
     */
    private double savedWidth = 1280;
    private double savedHeight = 820;

    /**
     * JavaFX 应用的核心方法，负责初始化和显示主界面
     * @param primaryStage 主舞台（窗口），由 JavaFX 运行时自动创建
     */
    @Override
    public void start(Stage primaryStage) {
        if (SingleInstanceChecker.isAlreadyRunning()) {
            logger.info("检测到已有实例运行，退出");
            Platform.exit();
            return;
        }
        logger.info("AhaKey Studio 启动中...");
        
        this.primaryStage = primaryStage;

        Platform.setImplicitExit(false);

        initLanguage();

        controller = new StudioController();
        
        // 2. 条件初始化语音输入管理器（根据 model.enabled 配置）
        if (com.example.ahakey.config.ModelConfig.getInstance().isEnabled()) {
            initVoiceInputManager();
        } else {
            logger.info("本地模型已禁用 (model.enabled=false)，跳过语音输入初始化");
        }
        
        // 3. 初始化系统托盘
        initSystemTray();
        
        // 4. 配置主窗口（Stage）属性
        primaryStage.setTitle("AhaKey Studio");      // 窗口标题
        primaryStage.setMinWidth(1024);             // Preserve panel geometry on narrow windows.
        primaryStage.setMinHeight(640);
        primaryStage.setWidth(1280);                 // 默认宽度
        primaryStage.setHeight(820);                 // 默认高度
        primaryStage.getIcons().add(new Image(getClass().getResourceAsStream("/ahakey.jpg")));

        // 3. 创建根布局容器
        // BorderPane 是一个边界布局，分为五个区域：top、bottom、left、right、center
        // 类比于 Web 中的 <header> + <footer> + <aside> + <main> 布局
        BorderPane root = new BorderPane();
        root.getStyleClass().add("root");  // 添加 CSS 样式类

        // 4. 创建各个 UI 组件
        
        // TopBar（顶部导航栏）：包含连接状态、模式选择、AhaType开关等
        TopBar topBar = new TopBar(
            controller, 
            controller.getDeviceStatus(), 
            controller.getStudioState(), 
            controller.getAgentManager()
        );
        
        // 设置语音输入管理器（仅当模型启用时）
        if (voiceInputManager != null) {
            topBar.setVoiceInputManager(voiceInputManager);
        }
        
        // 中间区域：使用 HBox 水平排列两个面板
        HBox centerPane = new HBox();
        centerPane.getStyleClass().add("workspace");
        centerPane.setMinWidth(1100); // Scroll instead of compressing the keyboard preview.
        
        // CanvasPane（画布面板）：显示键盘布局预览
        CanvasPane canvasPane = new CanvasPane(controller);
        HBox.setHgrow(canvasPane, Priority.ALWAYS);
        
        // InspectorPane（检查器面板）：显示当前选中按键的详细配置
        InspectorPane inspectorPane = new InspectorPane(controller);
        HBox.setHgrow(inspectorPane, Priority.NEVER);
        
        // 将两个面板添加到水平容器中
        centerPane.getChildren().addAll(canvasPane, inspectorPane);
        
        // 包裹在 ScrollPane 中：跨屏幕拖拽时 DPI 变化不会导致变形
        ScrollPane centerScroll = new ScrollPane(centerPane);
        centerScroll.setFitToWidth(false);
        centerScroll.setFitToHeight(true);
        centerScroll.setHbarPolicy(ScrollPane.ScrollBarPolicy.AS_NEEDED);
        centerScroll.setVbarPolicy(ScrollPane.ScrollBarPolicy.NEVER);
        centerScroll.setPannable(false);
        centerScroll.setStyle("-fx-background: transparent; -fx-background-color: transparent;");

        canvasPane.prefWidthProperty().bind(Bindings.createDoubleBinding(
            () -> Math.max(460, centerScroll.getViewportBounds().getWidth() * 0.52),
            centerScroll.viewportBoundsProperty()
        ));
        inspectorPane.prefWidthProperty().bind(Bindings.createDoubleBinding(
            () -> Math.max(520, centerScroll.getViewportBounds().getWidth() * 0.48),
            centerScroll.viewportBoundsProperty()
        ));
        
        // StatusBar（底部状态栏）：显示同步状态、连接状态等
        StatusBar statusBar = new StatusBar(
            controller.getDeviceStatus(), 
            controller.getStudioState()
        );

        // 5. 将组件组装到根布局中
        root.setTop(topBar);        // 顶部：导航栏
        root.setCenter(centerScroll); // 中间：工作区（画布 + 检查器，可滚动）
        root.setBottom(statusBar);  // 底部：状态栏

        // 6. 创建场景（Scene）并设置样式
        // Scene 是所有 UI 元素的容器，必须绑定到 Stage 才能显示
        Scene scene = new Scene(root);
        // 加载 CSS 样式文件，类比于 Web 中的 <link rel="stylesheet">
        scene.getStylesheets().add(getClass().getResource("/style.css").toExternalForm());
        primaryStage.setScene(scene);

        // 7. 设置窗口显示相关的监听器
        // 监听窗口显示状态，在窗口首次显示时触发 CSS 样式应用和布局计算
        primaryStage.showingProperty().addListener((obs, old, showing) -> {
            if (showing) {
                Platform.runLater(() -> {
                    root.applyCss();
                    root.layout();
                });
            }
        });

        // JavaFX performs per-monitor scaling. Only request a fresh layout
        // after a screen/size change; never force another monitor's pixel
        // dimensions onto the current monitor.
        PauseTransition layoutRefresh = new PauseTransition(Duration.millis(150));
        layoutRefresh.setOnFinished(e -> Platform.runLater(() -> {
            root.applyCss();
            root.requestLayout();
        }));

        // 监听窗口位置和尺寸变化
        javafx.beans.value.ChangeListener<Number> posSizeListener = (obs, old, val) -> {
            layoutRefresh.stop();
            layoutRefresh.playFromStart();
        };
        primaryStage.xProperty().addListener(posSizeListener);
        primaryStage.yProperty().addListener(posSizeListener);
        primaryStage.widthProperty().addListener(posSizeListener);
        primaryStage.heightProperty().addListener(posSizeListener);

        // 8. 显示窗口
        primaryStage.show();
        
        // 10. 设置窗口关闭时的逻辑：最小化到系统托盘
        // 类比于 Web 中的 beforeunload 事件
        primaryStage.setOnCloseRequest(event -> {
            if (SystemTray.isSupported()) {
                event.consume(); // 阻止默认关闭行为
                minimizeToTray();
            } else {
                shutdownApplication();
            }
        });
        
        // 11. 设置窗口最小化时隐藏到托盘
        primaryStage.iconifiedProperty().addListener((obs, oldVal, newVal) -> {
            if (newVal && SystemTray.isSupported()) {
                minimizeToTray();
            }
        });
    }

    @Override
    public void stop() {
        shutdownApplication();
    }

    /**
     * 初始化系统托盘
     */
    private void initLanguage() {
        try {
            LanguageManager languageManager = LanguageManager.getInstance();
            
            java.io.File prefsDir = new java.io.File(
                System.getProperty("user.home"), ".ahakey"
            );
            java.io.File prefsFile = new java.io.File(prefsDir, "preferences.properties");
            
            if (prefsFile.exists()) {
                java.util.Properties prefs = new java.util.Properties();
                try (java.io.FileInputStream fis = new java.io.FileInputStream(prefsFile)) {
                    prefs.load(fis);
                    String savedLang = prefs.getProperty("AhaKeySelectedLanguage");
                    if (savedLang != null && !savedLang.isEmpty()) {
                        languageManager.switchLanguage(savedLang);
                    }
                }
            }
            
            logger.info("语言设置初始化完成，当前语言: {}", languageManager.getCurrentLanguage());
        } catch (Exception e) {
            logger.warn("初始化语言设置失败: {}", e.getMessage());
        }
    }
    
    private void initSystemTray() {
        if (!SystemTray.isSupported()) {
            logger.warn("系统托盘不受支持");
            return;
        }
        
        try {
            // 创建弹出菜单
            PopupMenu popupMenu = new PopupMenu();
            
            // 退出菜单项（使用英文避免中文乱码）
            MenuItem exitItem = new MenuItem("Exit");
            exitItem.addActionListener(e -> shutdownApplication());
            popupMenu.add(exitItem);
            
            // 创建托盘图标
            java.awt.Image image = Toolkit.getDefaultToolkit().getImage(
                getClass().getResource("/ahakey.jpg")
            );
            trayIcon = new TrayIcon(image, "AhaKey Studio", popupMenu);
            
            // 设置图标大小自适应
            trayIcon.setImageAutoSize(true);
            
            // 添加鼠标点击事件：左键单击显示窗口（右键菜单由系统自动处理）
            trayIcon.addMouseListener(new MouseAdapter() {
                @Override
                public void mouseClicked(MouseEvent e) {
                    if (e.getButton() == MouseEvent.BUTTON1) {
                        showFromTray();
                    }
                }
            });
            
            // 添加到系统托盘
            SystemTray.getSystemTray().add(trayIcon);
            logger.info("系统托盘图标已添加");
            
        } catch (Exception e) {
            logger.error("初始化系统托盘失败: {}", e.getMessage());
            trayIcon = null;
        }
    }
    
    /**
     * 最小化到系统托盘
     */
    private void minimizeToTray() {
        Platform.runLater(() -> {
            // 保存当前窗口尺寸
            savedWidth = primaryStage.getWidth();
            savedHeight = primaryStage.getHeight();
            
            primaryStage.setIconified(false);
            primaryStage.hide();
            if (trayIcon != null) {
                trayIcon.displayMessage("AhaKey Studio", "应用已最小化到托盘", TrayIcon.MessageType.INFO);
            }
        });
    }
    
    /**
     * 从系统托盘显示窗口
     */
    private void showFromTray() {
        Platform.runLater(() -> {
            // 恢复之前保存的窗口尺寸
            primaryStage.setWidth(savedWidth);
            primaryStage.setHeight(savedHeight);
            
            // 取消图标化状态，显示窗口并置于前端
            primaryStage.setIconified(false);
            primaryStage.show();
            primaryStage.toFront();
        });
    }
    
    private void shutdownApplication() {
        if (shuttingDown) {
            return;
        }
        shuttingDown = true;
        try {
            // 移除系统托盘图标（使用局部变量避免竞态条件）
            TrayIcon iconToRemove = trayIcon;
            trayIcon = null;
            if (iconToRemove != null) {
                try {
                    SystemTray.getSystemTray().remove(iconToRemove);
                } catch (Exception e) {
                    logger.warn("移除系统托盘图标失败: {}", e.getMessage());
                }
            }
            
            shutdownVoiceInputManager();
            if (controller != null) {
                controller.shutdown();
            }
            
            stopBleDriverProcess();
        } catch (Exception e) {
            logger.warn("Application shutdown cleanup failed: {}", e.getMessage());
        } finally {
            Platform.exit();
            System.exit(0);
        }
    }
    
    private void stopBleDriverProcess() {
        try {
            logger.info("停止 BLE_tcp_driver.exe 进程...");
            new ProcessBuilder("taskkill", "/F", "/IM", "BLE_tcp_driver.exe").redirectErrorStream(true).start().waitFor();
            Thread.sleep(300);
            logger.info("BLE_tcp_driver.exe 进程已停止");
        } catch (Exception e) {
            logger.warn("停止 BLE_tcp_driver.exe 进程失败: {}", e.getMessage());
        }
    }
    
    /**
     * 初始化语音输入管理器
     */
    private void initVoiceInputManager() {
        logger.info("初始化语音输入管理器 (SenseVoice-Small)...");
        try {
            voiceInputManager = new VoiceInputManager();
            voiceInputManager.initialize();
            
            // 配置语音键回调：按下开始录音，释放停止录音
            if (WindowsVoiceTyping.isWindows()) {
                WindowsVoiceRelayService relay = WindowsVoiceRelayService.getInstance();
                relay.setOnVoiceKeyDown(() -> {
                    if (voiceInputManager != null && voiceInputManager.isActivated()) {
                        voiceInputManager.startRecording();
                    }
                });
                relay.setOnVoiceKeyUp(() -> {
                    if (voiceInputManager != null && voiceInputManager.isRecording()) {
                        voiceInputManager.stopRecording();
                    }
                });
                // 配置模拟录音回调（用于模拟按钮直接触发录音）
                relay.setOnSimulateRecordStart(() -> {
                    if (voiceInputManager != null && voiceInputManager.isActivated()) {
                        voiceInputManager.startRecording();
                    }
                });
                relay.setOnSimulateRecordStop(() -> {
                    if (voiceInputManager != null && voiceInputManager.isRecording()) {
                        voiceInputManager.stopRecording();
                    }
                });
            }
            
            logger.info("语音输入管理器初始化成功");
        } catch (Exception e) {
            logger.error("语音输入管理器初始化失败: {}", e.getMessage());
            // 语音输入功能不可用，但不影响主应用运行
            voiceInputManager = null;
        }
    }
    
    /**
     * 关闭语音输入管理器
     */
    private void shutdownVoiceInputManager() {
        if (voiceInputManager != null) {
            logger.info("关闭语音输入管理器...");
            voiceInputManager.shutdown();
        }
    }
    
    /**
     * 获取语音输入管理器实例
     */
    public VoiceInputManager getVoiceInputManager() {
        return voiceInputManager;
    }

    /**
     * 程序入口方法
     * JavaFX 应用必须通过 launch() 方法启动，它会自动调用 init() 和 start()
     * @param args 命令行参数
     */
    public static void main(String[] args) {
        launch(args);
    }
    
}
