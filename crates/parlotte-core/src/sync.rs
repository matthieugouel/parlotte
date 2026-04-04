use matrix_sdk::config::SyncSettings;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use crate::error::{ParlotteError, Result};

/// Manages the Matrix sync loop lifecycle.
pub(crate) struct SyncManager {
    running: Arc<AtomicBool>,
}

impl SyncManager {
    pub fn new() -> Self {
        Self {
            running: Arc::new(AtomicBool::new(false)),
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

    /// Start a continuous sync loop in the background.
    /// Returns a handle that can be used to stop the sync.
    pub fn start_sync(
        &self,
        client: matrix_sdk::Client,
    ) -> Result<SyncHandle> {
        if self.running.swap(true, Ordering::SeqCst) {
            return Err(ParlotteError::Sync {
                message: "sync is already running".to_string(),
            });
        }

        let running = self.running.clone();

        let handle = tokio::spawn(async move {
            let settings = SyncSettings::default();
            // sync() runs until the client is dropped or an error occurs
            let result = client.sync(settings).await;
            running.store(false, Ordering::SeqCst);
            result
        });

        Ok(SyncHandle {
            _handle: handle,
            running: self.running.clone(),
        })
    }

    pub fn stop(&self) {
        self.running.store(false, Ordering::SeqCst);
    }
}

/// Handle to a running sync loop.
pub struct SyncHandle {
    _handle: tokio::task::JoinHandle<std::result::Result<(), matrix_sdk::Error>>,
    running: Arc<AtomicBool>,
}

impl SyncHandle {
    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::SeqCst)
    }
}

impl Drop for SyncHandle {
    fn drop(&mut self) {
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
