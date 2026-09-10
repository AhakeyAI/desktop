use crate::{backend, settings::Provider, state::Runtime};
use tauri::{
    menu::{CheckMenuItem, IsMenuItem, Menu, MenuItem, PredefinedMenuItem, Submenu},
    Emitter, Manager,
};

#[derive(Clone)]
pub struct Controls {
    providers: Vec<(Provider, CheckMenuItem<tauri::Wry>)>,
    profiles: Vec<(String, CheckMenuItem<tauri::Wry>)>,
    captions: CheckMenuItem<tauri::Wry>,
    voices_menu: Submenu<tauri::Wry>,
    profiles_menu: Submenu<tauri::Wry>,
    last: Option<(Provider, String, bool)>,
}
fn provider_label(provider: &Provider) -> &'static str {
    match provider {
        Provider::Wechat => "微信输入法",
        Provider::WindowsNative => "Windows 听写",
        Provider::Local => "本地 SenseVoice",
        Provider::Doubao => "豆包云端",
    }
}
fn provider_id(provider: &Provider) -> &'static str {
    match provider {
        Provider::Wechat => "wechat",
        Provider::WindowsNative => "windows-native",
        Provider::Local => "local",
        Provider::Doubao => "doubao",
    }
}
#[derive(Debug, PartialEq)]
enum Action {
    Provider(Provider),
    Profile(String),
    Captions,
    Preview,
    Open,
    Quit,
}
fn parse(id: &str) -> Option<Action> {
    Some(match id {
        "provider:wechat" => Action::Provider(Provider::Wechat),
        "provider:windows-native" => Action::Provider(Provider::WindowsNative),
        "provider:local" => Action::Provider(Provider::Local),
        "provider:doubao" => Action::Provider(Provider::Doubao),
        "captions" => Action::Captions,
        "caption-preview" => Action::Preview,
        "open" => Action::Open,
        "quit" => Action::Quit,
        _ => {
            let profile = id.strip_prefix("profile:")?;
            if !crate::settings::default_profiles()
                .iter()
                .any(|p| p.id == profile)
            {
                return None;
            }
            Action::Profile(profile.into())
        }
    })
}
fn show_main(app: &tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
        let _ = w.set_focus();
    }
}
pub async fn apply_action(app: &tauri::AppHandle, id: &str) -> Result<(), String> {
    let action = parse(id).ok_or("不支持的快捷操作")?;
    let result = match action {
        Action::Open => {
            show_main(app);
            Ok(())
        }
        Action::Quit => {
            backend::request_shutdown(app);
            Ok(())
        }
        Action::Provider(provider) => {
            if !cfg!(windows) && matches!(provider, Provider::Wechat | Provider::WindowsNative) {
                return Err("此平台不支持该输入法".into());
            }
            backend::apply_settings(app, backend::SettingsEdit::Provider(provider))
                .await
                .map(|_| ())
        }
        Action::Profile(profile) => {
            backend::apply_settings(app, backend::SettingsEdit::Profile(profile))
                .await
                .map(|_| ())
        }
        Action::Captions => {
            let settings =
                backend::apply_settings(app, backend::SettingsEdit::ToggleCaptions).await?;
            if settings.captions_enabled {
                backend::preview_caption(app)
            } else {
                Ok(())
            }
        }
        Action::Preview => {
            let enabled = app
                .state::<Runtime>()
                .settings
                .lock()
                .unwrap()
                .captions_enabled;
            if !enabled {
                backend::apply_settings(app, backend::SettingsEdit::ToggleCaptions).await?;
            }
            backend::preview_caption(app)
        }
    };
    sync_inner(app, true);
    result
}
pub fn install(app: &tauri::App) -> tauri::Result<()> {
    let settings = app.state::<Runtime>().settings.lock().unwrap().clone();
    let mut providers = vec![];
    for provider in [
        Provider::Wechat,
        Provider::WindowsNative,
        Provider::Local,
        Provider::Doubao,
    ] {
        if !cfg!(windows) && matches!(provider, Provider::Wechat | Provider::WindowsNative) {
            continue;
        }
        let item = CheckMenuItem::with_id(
            app,
            format!("provider:{}", provider_id(&provider)),
            provider_label(&provider),
            true,
            settings.provider == provider,
            None::<&str>,
        )?;
        providers.push((provider, item));
    }
    let voices_menu = Submenu::with_items(
        app,
        "语音识别",
        true,
        &providers
            .iter()
            .map(|(_, i)| i as &dyn IsMenuItem<tauri::Wry>)
            .collect::<Vec<_>>(),
    )?;
    let profiles = settings
        .profiles
        .iter()
        .map(|p| {
            Ok((
                p.id.clone(),
                CheckMenuItem::with_id(
                    app,
                    format!("profile:{}", p.id),
                    &p.name,
                    true,
                    p.id == settings.active_profile,
                    None::<&str>,
                )?,
            ))
        })
        .collect::<tauri::Result<Vec<_>>>()?;
    let profiles_menu = Submenu::with_items(
        app,
        "Profile",
        true,
        &profiles
            .iter()
            .map(|(_, i)| i as &dyn IsMenuItem<tauri::Wry>)
            .collect::<Vec<_>>(),
    )?;
    let captions = CheckMenuItem::with_id(
        app,
        "captions",
        "桌面字幕",
        true,
        settings.captions_enabled,
        None::<&str>,
    )?;
    let preview = MenuItem::with_id(app, "caption-preview", "预览字幕位置", true, None::<&str>)?;
    let open = MenuItem::with_id(app, "open", "打开 AhaKey Studio", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let separator2 = PredefinedMenuItem::separator(app)?;
    let menu = Menu::with_items(
        app,
        &[
            &open,
            &separator,
            &voices_menu,
            &profiles_menu,
            &captions,
            &preview,
            &separator2,
            &quit,
        ],
    )?;
    *app.state::<Runtime>().tray_controls.lock().unwrap() = Some(Controls {
        providers,
        profiles,
        captions,
        voices_menu,
        profiles_menu,
        last: None,
    });
    if let Some(icon) = app.default_window_icon().cloned() {
        let tray = tauri::tray::TrayIconBuilder::with_id("main-tray")
            .icon(icon)
            .menu(&menu)
            .tooltip("AhaKey Studio · 语音 / Profile / 字幕")
            .on_menu_event(|app, event| {
                let app = app.clone();
                let id = event.id.as_ref().to_owned();
                tauri::async_runtime::spawn(async move {
                    if let Err(error) = apply_action(&app, &id).await {
                        sync_inner(&app, true);
                        let _ = app.emit("native-error", error);
                        show_main(&app);
                    }
                });
            })
            .build(app);
        app.state::<Runtime>()
            .tray
            .store(tray.is_ok(), std::sync::atomic::Ordering::SeqCst);
    }
    sync_inner(app.handle(), true);
    Ok(())
}
pub fn sync(app: &tauri::AppHandle) {
    sync_inner(app, false)
}
fn sync_inner(app: &tauri::AppHandle, force: bool) {
    let app2 = app.clone();
    let _ = app.run_on_main_thread(move || {
        let state = app2.state::<Runtime>();
        let settings = state.settings.lock().unwrap().clone();
        let key = (
            settings.provider.clone(),
            settings.active_profile.clone(),
            settings.captions_enabled,
        );
        let controls = {
            let mut controls = state.tray_controls.lock().unwrap();
            let Some(c) = controls.as_mut() else { return };
            if !force && c.last.as_ref() == Some(&key) {
                return;
            }
            c.last = Some(key);
            c.clone()
        };
        for (provider, item) in &controls.providers {
            let _ = item.set_checked(*provider == settings.provider);
        }
        for (id, item) in &controls.profiles {
            let _ = item.set_checked(*id == settings.active_profile);
        }
        let _ = controls.captions.set_checked(settings.captions_enabled);
        let _ = controls
            .voices_menu
            .set_text(format!("语音识别 · {}", provider_label(&settings.provider)));
        if let Some(profile) = settings
            .profiles
            .iter()
            .find(|p| p.id == settings.active_profile)
        {
            let _ = controls
                .profiles_menu
                .set_text(format!("Profile · {}", profile.name));
        }
    });
}
#[tauri::command]
pub async fn quick_action(window: tauri::WebviewWindow, action: String) -> Result<(), String> {
    backend::require_main(&window)?;
    apply_action(window.app_handle(), &action).await
}
#[tauri::command]
pub fn tray_status(window: tauri::WebviewWindow) -> Result<serde_json::Value, String> {
    backend::require_main(&window)?;
    let controls = window
        .state::<Runtime>()
        .tray_controls
        .lock()
        .unwrap()
        .clone()
        .ok_or("托盘菜单不可用")?;
    let providers=controls.providers.iter().map(|(p,item)|Ok(serde_json::json!({"id":provider_id(p),"checked":item.is_checked().map_err(|e|e.to_string())?}))).collect::<Result<Vec<_>,String>>()?;
    let profiles = controls
        .profiles
        .iter()
        .map(|(p, item)| {
            Ok(serde_json::json!({"id":p,"checked":item.is_checked().map_err(|e|e.to_string())?}))
        })
        .collect::<Result<Vec<_>, String>>()?;
    Ok(
        serde_json::json!({"providers":providers,"profiles":profiles,"captions":controls.captions.is_checked().map_err(|e|e.to_string())?}),
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_known_actions_are_dispatched() {
        assert_eq!(
            parse("provider:wechat"),
            Some(Action::Provider(Provider::Wechat))
        );
        assert_eq!(
            parse("profile:chatgpt-app"),
            Some(Action::Profile("chatgpt-app".into()))
        );
        assert_eq!(parse("captions"), Some(Action::Captions));
        assert!(parse("profile:arbitrary").is_none());
        assert!(parse("run anything").is_none());
    }
}
