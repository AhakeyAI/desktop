package com.example.ahakey;

import com.example.ahakey.app.StudioController;
import com.example.ahakey.service.VoiceInputManager;
import com.example.ahakey.view.CanvasPane;
import com.example.ahakey.view.InspectorPane;
import com.example.ahakey.view.StatusBar;
import com.example.ahakey.view.TopBar;
import javafx.animation.PauseTransition;
import javafx.util.Duration;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.beans.binding.Bindings;
import javafx.geometry.Rectangle2D;
import javafx.scene.Scene;
import javafx.scene.control.ScrollPane;
import javafx.scene.image.Image;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.Region;
import javafx.stage.Screen;
import javafx.stage.Stage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * AhaKey Studio 主应用类 (Ubuntu/Linux 版本)
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
    
    private Stage primaryStage;

    /**
     * JavaFX 应用的核心方法，负责初始化和显示主界面
     * @param primaryStage 主舞台（窗口），由 JavaFX 运行时自动创建
     */
    @Override
    public void start(Stage primaryStage) {
        this.primaryStage = primaryStage;

        // 1. 创建主控制器，作为整个应用的核心协调者
        controller = new StudioController();
        
        // 2. 条件初始化语音输入管理器（根据 model.enabled 配置）
        if (com.example.ahakey.config.ModelConfig.getInstance().isEnabled()) {
            initVoiceInputManager();
        } else {
            logger.info("本地模型已禁用 (model.enabled=false)，跳过语音输入初始化");
        }
        
        // 3. 配置主窗口（Stage）属性
        primaryStage.setTitle("AhaKey Studio");      // 窗口标题
        primaryStage.setMinWidth(800);              // 最小宽度（分屏/多屏适配）
        primaryStage.setMinHeight(600);              // 最小高度
        primaryStage.setWidth(1280);                 // 默认宽度
        primaryStage.setHeight(820);                 // 默认高度
        primaryStage.getIcons().add(new Image(getClass().getResourceAsStream("/ahakey.jpg")));

        // 4. 创建根布局容器
        // BorderPane 是一个边界布局，分为五个区域：top、bottom、left、right、center
        // 类比于 Web 中的 <header> + <footer> + <aside> + <main> 布局
        BorderPane root = new BorderPane();
        root.getStyleClass().add("root");  // 添加 CSS 样式类

        // 5. 创建各个 UI 组件
        
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
        centerPane.setMinWidth(Region.USE_PREF_SIZE); // HBox 不缩小，由外层 ScrollPane 处理溢出
        
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
        centerScroll.setFitToWidth(true);
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

        // 6. 将组件组装到根布局中
        root.setTop(topBar);        // 顶部：导航栏
        root.setCenter(centerScroll); // 中间：工作区（画布 + 检查器，可滚动）
        root.setBottom(statusBar);  // 底部：状态栏

        // 7. 创建场景（Scene）并设置样式
        // Scene 是所有 UI 元素的容器，必须绑定到 Stage 才能显示
        Scene scene = new Scene(root);
        // 加载 CSS 样式文件，类比于 Web 中的 <link rel="stylesheet">
        scene.getStylesheets().add(getClass().getResource("/style.css").toExternalForm());
        primaryStage.setScene(scene);

        // 8. 设置窗口显示相关的监听器
        // 监听窗口显示状态，在窗口首次显示时触发 CSS 样式应用和布局计算
        primaryStage.showingProperty().addListener((obs, old, showing) -> {
            if (showing) {
                Platform.runLater(() -> {
                    root.applyCss();
                    root.layout();
                });
            }
        });

        // 9. 跨屏幕拖拽防护：记住高分屏窗口尺寸，拖回来时自动恢复
        // 问题场景：2880x1800(高DPI) → 1920x1080(低DPI) → 2880x1800，窗口被压缩无法恢复
        final double[] savedSize = {1280, 820}; // 保存高分屏的窗口尺寸
        final double[] lastScreenDpi = {0};     // 上次所在屏幕的 DPI

        PauseTransition layoutRefresh = new PauseTransition(Duration.millis(500));
        layoutRefresh.setOnFinished(e -> Platform.runLater(() -> {
            // 检测当前屏幕 DPI
            double currentDpi = getCurrentScreenDpi(primaryStage);
            
            if (lastScreenDpi[0] > 0 && currentDpi > lastScreenDpi[0] * 1.1) {
                // 从低DPI屏回到了高DPI屏，恢复保存的窗口尺寸
                logger.debug("检测到低DPI→高DPI切换 ({}→{})，恢复窗口尺寸 {}x{}",
                    (int) lastScreenDpi[0], (int) currentDpi, (int) savedSize[0], (int) savedSize[1]);
                primaryStage.setWidth(savedSize[0]);
                primaryStage.setHeight(savedSize[1]);
            }
            
            // 保存当前尺寸（如果窗口在高分屏上且尺寸足够大）
            if (currentDpi >= 120 || primaryStage.getWidth() >= 1100) {
                savedSize[0] = primaryStage.getWidth();
                savedSize[1] = primaryStage.getHeight();
            }
            
            lastScreenDpi[0] = currentDpi;
            
            // 强制刷新布局
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

        // 10. 设置窗口关闭时的逻辑
        primaryStage.setOnCloseRequest(event -> {
            shutdownApplication();
        });

        // 11. 显示窗口
        primaryStage.show();
    }

    @Override
    public void stop() {
        shutdownApplication();
    }

    private void shutdownApplication() {
        if (shuttingDown) {
            return;
        }
        shuttingDown = true;
        try {
            shutdownVoiceInputManager();
            if (controller != null) {
                controller.shutdown();
            }
        } catch (Exception e) {
            logger.warn("Application shutdown cleanup failed: {}", e.getMessage());
        } finally {
            Platform.exit();
            System.exit(0);
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
    
    /**
     * 获取窗口当前所在屏幕的 DPI
     * 通过比较窗口中心点与各屏幕边界来确定当前屏幕
     */
    private double getCurrentScreenDpi(Stage stage) {
        double centerX = stage.getX() + stage.getWidth() / 2;
        double centerY = stage.getY() + stage.getHeight() / 2;
        
        for (Screen screen : Screen.getScreens()) {
            Rectangle2D bounds = screen.getBounds();
            if (bounds.contains(centerX, centerY)) {
                return screen.getDpi();
            }
        }
        // 回退：使用主屏幕 DPI
        return Screen.getPrimary().getDpi();
    }
}
