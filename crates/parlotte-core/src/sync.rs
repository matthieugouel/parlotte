use matrix_sdk::config::SyncSettings;
use matrix_sdk::ruma::events::typing::SyncTypingEvent;
use matrix_sdk::LoopCtrl;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use crate::error::{ParlotteError, Result};

/// Callback trait for sync events.
/// Called on each successful sync response so the UI layer can refresh.
pub trait SyncListener: Send + Sync + 'static {
    fn on_sync_update(&self);

    /// Called when typing state changes in a room.
    /// `user_ids` contains the full set of currently-typing users (not a delta).
    fn on_typing_update(&self, _room_id: String, _user_ids: Vec<String>) {}
}

/// Manages the Matrix sync loop lifecycle.
pub(crate) struct SyncManager {
    running: Arc<AtomicBool>,
    stop_flag: Arc<AtomicBool>,
}

impl SyncManager {
    pub fn new() -> Self {
        Self {
            running: Arc::new(AtomicBool::new(false)),
            stop_flag: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::SeqCst)
    }

    /// Run a single sync request. Useful for tests and one-shot operations.
    pub async fn sync_once(client: &matrix_sdk::Client) -> Result<()> {
        client
            .sync_once(SyncSettings::default())
            .await
            .map_err(|e| ParlotteError::Sync {
                message: e.to_string(),
            })?;
        Ok(())
    }

    /// Start a persistent sync loop in the background.
    /// The listener is called after each successful sync response.
    /// Uses long-polling with a 30-second timeout for responsive updates.
    pub fn start_persistent_sync(
        &self,
        client: matrix_sdk::Client,
        runtime: &tokio::runtime::Runtime,
        listener: Arc<dyn SyncListener>,
    ) -> Result<()> {
        if self.running.swap(true, Ordering::SeqCst) {
            return Err(ParlotteError::Sync {
                message: "sync is already running".to_string(),
            });
        }

        self.stop_flag.store(false, Ordering::SeqCst);
        let running = self.running.clone();
        let stop_flag = self.stop_flag.clone();

        let settings = SyncSettings::default().timeout(Duration::from_secs(30));

        runtime.spawn(async move {
            tracing::debug!("persistent sync loop starting");

            // Register a global event handler for typing notifications.
            // Fires for every room when typing state changes during sync.
            let typing_listener = listener.clone();
            client.add_event_handler(
                move |event: SyncTypingEvent, room: matrix_sdk::Room| {
                    let listener = typing_listener.clone();
                    async move {
                        let room_id = room.room_id().to_string();
                        let user_ids: Vec<String> =
                            event.content.user_ids.iter().map(|uid| uid.to_string()).collect();
                        listener.on_typing_update(room_id, user_ids);
                    }
                },
            );

            let result = client
                .sync_with_callback(settings, |_response| {
                    let listener = listener.clone();
                    let stop_flag = stop_flag.clone();
                    async move {
                        listener.on_sync_update();
                        if stop_flag.load(Ordering::SeqCst) {
                            tracing::debug!("persistent sync loop stopping (stop requested)");
                            LoopCtrl::Break
                        } else {
                            LoopCtrl::Continue
                        }
                    }
                })
                .await;

            running.store(false, Ordering::SeqCst);
            match result {
                Ok(()) => tracing::debug!("persistent sync loop ended normally"),
                Err(e) => tracing::warn!("persistent sync loop ended with error: {e}"),
            }
        });

        Ok(())
    }

    /// Stop the persistent sync loop. The loop will exit after the current
    /// sync request completes (up to 30 seconds).
    pub fn stop(&self) {
        self.stop_flag.store(true, Ordering::SeqCst);
        self.running.store(false, Ordering::SeqCst);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sync_manager_initial_state() {
        let mgr = SyncManager::new();
        assert!(!mgr.is_running());
    }

    #[test]
    fn sync_manager_stop_when_not_running() {
        let mgr = SyncManager::new();
        // Stopping when not running should be a no-op
        mgr.stop();
        assert!(!mgr.is_running());
    }

    #[test]
    fn sync_manager_stop_sets_running_false() {
        let mgr = SyncManager::new();
        // Manually set running to true
        mgr.running.store(true, Ordering::SeqCst);
        assert!(mgr.is_running());
        mgr.stop();
        assert!(!mgr.is_running());
    }
}
