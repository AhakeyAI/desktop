use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Provider {
    Minimax,
    Glm,
    Kimi,
    Codex,
    Custom,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Mapping {
    pub label: String,
    pub pointer: String,
    pub used_percent: bool,
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Account {
    pub id: String,
    pub label: String,
    pub provider: Provider,
    pub international: bool,
    pub enabled: bool,
    pub warning_percent: u8,
    #[serde(default)]
    pub endpoint: String,
    #[serde(default)]
    pub mappings: Vec<Mapping>,
}
impl Account {
    pub fn validate(&self) -> Result<(), String> {
        if self.id.is_empty()
            || self.id.len() > 64
            || !self
                .id
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || c == b'-')
            || self.label.trim().is_empty()
            || self.label.chars().count() > 40
            || self.warning_percent > 100
            || self.mappings.len() > 8
        {
            return Err("账户标识、名称或警告阈值无效".into());
        }
        if self.provider == Provider::Custom {
            let url = reqwest::Url::parse(&self.endpoint)
                .map_err(|_| "自定义地址必须是完整 HTTPS URL")?;
            if self.endpoint.len() > 512
                || url.scheme() != "https"
                || url.host_str().is_none()
                || !url.username().is_empty()
                || url.password().is_some()
                || url.query().is_some()
                || url.fragment().is_some()
                || self.mappings.is_empty()
            {
                return Err("自定义来源需要无内嵌凭据/查询参数的 HTTPS 地址和字段映射".into());
            }
            for m in &self.mappings {
                if m.label.is_empty()
                    || m.label.chars().count() > 40
                    || !m.pointer.starts_with('/')
                    || m.pointer.len() > 256
                {
                    return Err(
                        "字段映射需要名称和 JSON Pointer，例如 /quota/remainingPercent".into(),
                    );
                }
            }
        } else if !self.endpoint.is_empty() || !self.mappings.is_empty() {
            return Err("内置服务不接受覆盖地址或字段映射".into());
        }
        Ok(())
    }
    pub fn endpoint(&self) -> &str {
        match (self.provider, self.international) {
            (Provider::Minimax, false) => {
                "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains"
            }
            (Provider::Minimax, true) => {
                "https://api.minimax.io/v1/api/openplatform/coding_plan/remains"
            }
            (Provider::Glm, false) => "https://open.bigmodel.cn/api/monitor/usage/quota/limit",
            (Provider::Glm, true) => "https://api.z.ai/api/monitor/usage/quota/limit",
            (Provider::Kimi, _) => "https://api.kimi.com/coding/v1/usages",
            (Provider::Custom, _) => &self.endpoint,
            (Provider::Codex, _) => "",
        }
    }
    // Binding to the destination prevents an edited custom URL receiving an old credential.
    pub fn credential_id(&self) -> String {
        format!("{}:{:?}:{}", self.id, self.provider, self.endpoint())
    }
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Cards {
    pub accounts: Vec<Account>,
    pub auto_refresh: bool,
    pub refresh_seconds: u64,
}
impl Default for Cards {
    fn default() -> Self {
        Self {
            accounts: [
                (Provider::Minimax, "minimax", "MiniMax"),
                (Provider::Glm, "glm", "智谱 GLM"),
                (Provider::Kimi, "kimi", "Kimi Coding"),
                (Provider::Codex, "codex", "Codex"),
            ]
            .into_iter()
            .map(|(provider, id, label)| Account {
                id: id.into(),
                label: label.into(),
                provider,
                international: false,
                enabled: true,
                warning_percent: 20,
                endpoint: String::new(),
                mappings: vec![],
            })
            .collect(),
            auto_refresh: false,
            refresh_seconds: 300,
        }
    }
}
impl Cards {
    pub fn validate(&self) -> Result<(), String> {
        if self.accounts.len() > 16 || !(60..=3600).contains(&self.refresh_seconds) {
            return Err("最多 16 个账户，刷新间隔为 60–3600 秒".into());
        }
        let mut ids = std::collections::HashSet::new();
        for a in &self.accounts {
            a.validate()?;
            if !ids.insert(&a.id) {
                return Err("账户标识重复".into());
            }
        }
        Ok(())
    }
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Window {
    pub id: String,
    pub label: String,
    pub remaining_percent: Option<f64>,
    pub resets_at: Option<i64>,
    pub window_minutes: Option<u64>,
}
fn number(v: &Value) -> Option<f64> {
    v.as_f64()
        .or_else(|| v.as_str()?.parse().ok())
        .filter(|v| v.is_finite())
}
fn percent(v: &Value) -> Option<f64> {
    number(v).filter(|v| (0.0..=100.0).contains(v))
}
fn timestamp(v: &Value) -> Option<i64> {
    if let Some(s) = v.as_str() {
        if let Ok(t) = chrono::DateTime::parse_from_rfc3339(s) {
            return Some(t.timestamp());
        }
    }
    let n = number(v)?;
    if n <= 0.0 || n > 253_402_300_799_000.0 {
        return None;
    }
    Some(if n >= 1_000_000_000_000.0 {
        (n / 1000.0) as i64
    } else {
        n as i64
    })
}
fn window(
    id: impl Into<String>,
    label: impl Into<String>,
    remaining: Option<f64>,
    reset: &Value,
    duration: Option<u64>,
) -> Window {
    Window {
        id: id.into(),
        label: label.into(),
        remaining_percent: remaining,
        resets_at: timestamp(reset),
        window_minutes: duration,
    }
}
fn ratio(v: &Value) -> Option<f64> {
    let total = number(&v["limit"])?;
    let left = number(&v["remaining"])?;
    (total > 0.0 && left >= 0.0 && left <= total).then_some(left / total * 100.0)
}
pub fn parse(account: &Account, body: &Value) -> Result<Vec<Window>, String> {
    let mut out = vec![];
    match account.provider {
        Provider::Minimax => {
            if body.get("base_resp").is_some()
                && body["base_resp"]["status_code"].as_i64() != Some(0)
            {
                return Err("MiniMax 返回服务错误；未更新额度".into());
            }
            if let Some(item) = body["model_remains"]
                .as_array()
                .and_then(|items| items.iter().find(|v| v["model_name"] == "general"))
            {
                if item.get("current_interval_remaining_percent").is_some() {
                    out.push(window(
                        "interval",
                        "5 小时",
                        percent(&item["current_interval_remaining_percent"]),
                        &item["end_time"],
                        Some(300),
                    ));
                }
                if item["current_weekly_status"].as_i64() == Some(1) {
                    out.push(window(
                        "weekly",
                        "每周",
                        percent(&item["current_weekly_remaining_percent"]),
                        &item["weekly_end_time"],
                        Some(10080),
                    ));
                }
            }
        }
        Provider::Glm => {
            if body["success"] == false {
                return Err("GLM 返回服务错误；未更新额度".into());
            }
            if let Some(items) = body["data"]["limits"].as_array() {
                for (i, item) in items.iter().enumerate() {
                    if !item["type"].as_str().is_some_and(|v| {
                        v.eq_ignore_ascii_case("TOKENS_LIMIT")
                            || v.eq_ignore_ascii_case("CREDIT_LIMIT")
                    }) {
                        continue;
                    }
                    let (name, duration) = match item["unit"].as_u64() {
                        Some(3) => (
                            "小时窗口",
                            item["number"].as_u64().and_then(|n| n.checked_mul(60)),
                        ),
                        Some(6) => ("每周", Some(10080)),
                        _ => ("未标明周期", None),
                    };
                    out.push(window(
                        format!("limit-{i}"),
                        name,
                        percent(&item["percentage"]).map(|p| 100.0 - p),
                        &item["nextResetTime"],
                        duration,
                    ));
                }
            }
        }
        Provider::Kimi => {
            if let Some(items) = body["limits"].as_array() {
                for (i, item) in items.iter().enumerate() {
                    if let Some(detail) = item.get("detail") {
                        out.push(window(
                            format!("limit-{i}"),
                            format!("周期额度 {}", i + 1),
                            ratio(detail),
                            &detail["resetTime"],
                            None,
                        ));
                    }
                }
            }
            if let Some(detail) = body.get("usage") {
                out.push(window(
                    "total",
                    "套餐总额度",
                    ratio(detail),
                    &detail["resetTime"],
                    None,
                ));
            }
        }
        Provider::Codex => {
            let single;
            let buckets: Vec<(&str, &Value)> = if let Some(map) = body["rateLimitsByLimitId"]
                .as_object()
                .filter(|m| !m.is_empty())
            {
                map.iter().map(|(k, v)| (k.as_str(), v)).collect()
            } else {
                single = body
                    .get("rateLimits")
                    .ok_or("Codex 未返回额度；请确认使用官方账户登录")?;
                vec![("codex", single)]
            };
            for (id, bucket) in buckets {
                for key in ["primary", "secondary"] {
                    if let Some(item) = bucket.get(key).filter(|v| v.is_object()) {
                        let minutes = item["windowDurationMins"].as_u64().filter(|n| *n > 0);
                        let label = minutes
                            .map(|m| format!("{id} · {m} 分钟"))
                            .unwrap_or_else(|| format!("{id} · {key}"));
                        out.push(window(
                            format!("{id}-{key}"),
                            label,
                            percent(&item["usedPercent"]).map(|p| 100.0 - p),
                            &item["resetsAt"],
                            minutes,
                        ));
                    }
                }
            }
        }
        Provider::Custom => {
            for (i, m) in account.mappings.iter().enumerate() {
                let p = body.pointer(&m.pointer).and_then(percent).map(|p| {
                    if m.used_percent {
                        100.0 - p
                    } else {
                        p
                    }
                });
                out.push(window(
                    format!("custom-{i}"),
                    &m.label,
                    p,
                    &Value::Null,
                    None,
                ));
            }
        }
    }
    if out.is_empty() {
        Err("响应中没有可识别的额度窗口；不会用零替代".into())
    } else {
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    fn a(provider: Provider) -> Account {
        let mut a = Cards::default().accounts[0].clone();
        a.provider = provider;
        a
    }
    #[test]
    fn missing_and_zero_are_distinct() {
        let w=parse(&a(Provider::Glm),&json!({"data":{"limits":[{"type":"TOKENS_LIMIT","percentage":100,"unit":6},{"type":"TOKENS_LIMIT"}]}})).unwrap();
        assert_eq!(w[0].remaining_percent, Some(0.0));
        assert_eq!(w[1].remaining_percent, None);
        assert_eq!(w[1].window_minutes, None);
    }
    #[test]
    fn minimax_inactive_week_is_not_unlimited() {
        let w=parse(&a(Provider::Minimax),&json!({"model_remains":[{"model_name":"general","current_interval_remaining_percent":75,"current_weekly_status":3,"current_weekly_remaining_percent":100}]})).unwrap();
        assert_eq!(w.len(), 1);
        assert_eq!(w[0].remaining_percent, Some(75.0));
    }
    #[test]
    fn kimi_missing_total_never_fabricates_percentage() {
        let w = parse(&a(Provider::Kimi), &json!({"usage":{"remaining":0}})).unwrap();
        assert_eq!(w[0].remaining_percent, None);
    }
    #[test]
    fn codex_retains_every_bucket_and_actual_window() {
        let w=parse(&a(Provider::Codex),&json!({"rateLimitsByLimitId":{"one":{"primary":{"usedPercent":25,"windowDurationMins":15}},"two":{"secondary":{"usedPercent":0,"windowDurationMins":10080}}}})).unwrap();
        assert_eq!(w.len(), 2);
        assert_eq!(w[0].remaining_percent, Some(75.0));
        assert_eq!(w[0].window_minutes, Some(15));
    }
    #[test]
    fn range_errors_are_unknown_not_clamped() {
        assert_eq!(percent(&json!(101)), None);
        assert_eq!(percent(&json!(-1)), None);
        assert_eq!(percent(&json!("0")), Some(0.0));
    }
    #[test]
    fn reset_seconds_millis_and_iso_agree() {
        let t = 1_800_000_000;
        assert_eq!(timestamp(&json!(t)), timestamp(&json!(t * 1000_i64)));
        assert_eq!(timestamp(&json!("2027-01-15T08:00:00Z")), Some(t));
    }
    #[test]
    fn custom_maps_fields_without_executing_code() {
        let mut account = a(Provider::Custom);
        account.endpoint = "https://example.com/quota".into();
        account.mappings = vec![Mapping {
            label: "余额".into(),
            pointer: "/quota/pct".into(),
            used_percent: true,
        }];
        account.validate().unwrap();
        let w = parse(&account, &json!({"quota":{"pct":20}})).unwrap();
        assert_eq!(w[0].remaining_percent, Some(80.0));
        account.endpoint = "https://user:secret@example.com/quota".into();
        assert!(account.validate().is_err());
    }
    #[test]
    fn identity_and_schema_reject_path_traversal_and_plaintext_keys() {
        let mut cards = Cards::default();
        cards.accounts[0].id = "../key".into();
        assert!(cards.validate().is_err());
        let mut v = serde_json::to_value(Cards::default()).unwrap();
        v["accounts"][0]["apiKey"] = json!("never-save-me");
        assert!(serde_json::from_value::<Cards>(v).is_err());
    }
}
