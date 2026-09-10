use serde::Serialize;

#[derive(Debug, Clone, Serialize, PartialEq, Default)]
#[serde(rename_all = "camelCase")]
pub struct Caption {
    pub phase: String,
    pub text: String,
    pub sequence: u64,
}

impl Caption {
    pub fn idle() -> Self {
        Self {
            phase: "idle".into(),
            text: String::new(),
            sequence: 0,
        }
    }
    #[cfg(test)]
    pub fn test_press(&mut self) {
        self.sequence += 1;
        self.phase = "listening".into();
        self.text = "已收到按下 · 字幕位置测试，未录音".into();
    }
    #[cfg(test)]
    pub fn test_release(&mut self) {
        self.sequence += 1;
        self.phase = "final".into();
        self.text = "已收到松开 · 按键与字幕窗口测试完成".into();
    }
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Placement {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

pub fn place(left: i32, top: i32, right: i32, bottom: i32, scale: f64, offset: u32) -> Placement {
    let margin = (16.0 * scale).round() as i32;
    let width = ((560.0 * scale).round() as i32).min((right - left - 2 * margin).max(1));
    let height = ((106.0 * scale).round() as i32).min((bottom - top).max(1));
    Placement {
        x: left + (right - left - width) / 2,
        y: (bottom - height - (f64::from(offset) * scale).round() as i32).max(top),
        width: width as u32,
        height: height as u32,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn different_dpi_and_vertical_monitor_layouts_stay_in_target_work_area() {
        for (left, top, right, bottom, scale) in [
            (0, -1440, 2560, 0, 1.5),
            (1920, 0, 5760, 2080, 2.0),
            (-2560, 120, 0, 1520, 1.25),
        ] {
            let p = place(left, top, right, bottom, scale, 20);
            assert!(p.x >= left && p.y >= top);
            assert!(p.x + p.width as i32 <= right && p.y + p.height as i32 <= bottom);
            assert!((p.x + p.width as i32 / 2 - (left + right) / 2).abs() <= 1);
        }
    }
    #[test]
    fn places_on_negative_origin_secondary_monitor_above_taskbar() {
        let p = place(-1920, 0, 0, 1040, 1.0, 20);
        assert_eq!(
            p,
            Placement {
                x: -1240,
                y: 914,
                width: 560,
                height: 106
            }
        );
    }
    #[test]
    fn uses_target_monitor_dpi_and_clamps_small_screen() {
        let p = place(1920, 0, 4480, 1400, 1.5, 20);
        assert_eq!(p.width, 840);
        assert_eq!(p.y, 1211);
        let small = place(0, 0, 320, 100, 2.0, 160);
        assert!(small.x >= 0 && small.y >= 0 && small.width <= 320 && small.height <= 100);
    }
    #[test]
    fn distinguishes_test_from_recognition_and_sequences_results() {
        let mut caption = Caption::idle();
        caption.test_press();
        assert_eq!(caption.phase, "listening");
        assert!(caption.text.contains("未录音"));
        caption.test_release();
        assert_eq!(caption.phase, "final");
        assert_eq!(caption.sequence, 2);
    }
}
