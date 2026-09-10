use crate::settings::TriggerMode;

#[derive(Default)]
pub struct KeyTest {
    was_down: bool,
    active: bool,
    mode: Option<TriggerMode>,
}

impl KeyTest {
    pub fn stop(&mut self) -> Option<bool> {
        let changed = self.active;
        *self = Self::default();
        changed.then_some(false)
    }

    pub fn update(&mut self, down: bool, mode: TriggerMode) -> Option<bool> {
        // A mode change ends the old session instead of leaving a toggle latched.
        if self.mode.as_ref().is_some_and(|previous| *previous != mode) {
            let was_active = self.active;
            self.was_down = down;
            self.active = false;
            self.mode = Some(mode);
            return was_active.then_some(false);
        }
        self.mode = Some(mode.clone());
        let event = if down && !self.was_down {
            self.active = if mode == TriggerMode::Toggle {
                !self.active
            } else {
                true
            };
            Some(self.active)
        } else if !down && self.was_down && mode == TriggerMode::Hold && self.active {
            self.active = false;
            Some(false)
        } else {
            None
        };
        self.was_down = down;
        event
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn repeated_presses_keep_hold_edges_paired() {
        let mut input = KeyTest::default();
        for _ in 0..100 {
            assert_eq!(input.update(true, TriggerMode::Hold), Some(true));
            assert_eq!(input.update(true, TriggerMode::Hold), None);
            assert_eq!(input.update(false, TriggerMode::Hold), Some(false));
            assert_eq!(input.update(false, TriggerMode::Hold), None);
        }
        assert_eq!(input.stop(), None);
        assert_eq!(input.update(true, TriggerMode::Hold), Some(true));
        assert_eq!(input.stop(), Some(false));
    }
    #[test]
    fn hold_has_one_start_and_one_end_without_repeat() {
        let mut input = KeyTest::default();
        assert_eq!(input.update(true, TriggerMode::Hold), Some(true));
        assert_eq!(input.update(true, TriggerMode::Hold), None);
        assert_eq!(input.update(false, TriggerMode::Hold), Some(false));
        assert_eq!(input.update(false, TriggerMode::Hold), None);
    }
    #[test]
    fn toggle_ends_on_next_down_and_disable_cancels_active_session() {
        let mut input = KeyTest::default();
        assert_eq!(input.update(true, TriggerMode::Toggle), Some(true));
        assert_eq!(input.update(false, TriggerMode::Toggle), None);
        assert_eq!(input.update(true, TriggerMode::Toggle), Some(false));
        input.update(false, TriggerMode::Toggle);
        input.update(true, TriggerMode::Toggle);
        assert_eq!(input.stop(), Some(false));
        assert_eq!(input.stop(), None);
    }
    #[test]
    fn changing_mode_cannot_leave_session_stuck() {
        let mut input = KeyTest::default();
        input.update(true, TriggerMode::Toggle);
        input.update(false, TriggerMode::Toggle);
        assert_eq!(input.update(false, TriggerMode::Hold), Some(false));
        assert_eq!(input.update(true, TriggerMode::Hold), Some(true));
    }
}
