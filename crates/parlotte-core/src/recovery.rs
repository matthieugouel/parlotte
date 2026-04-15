use matrix_sdk::encryption::recovery::RecoveryState as SdkRecoveryState;

/// State of the user's encrypted-backup / secret-storage setup.
///
/// Mirrors `matrix_sdk::encryption::recovery::RecoveryState` so the FFI and UI
/// layers don't depend on the SDK directly.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryState {
    /// State has not been determined yet (e.g. initial sync hasn't completed).
    Unknown,
    /// Secret storage is set up and all secrets are cached locally.
    Enabled,
    /// No default secret storage key exists, or it was explicitly disabled.
    Disabled,
    /// Secret storage exists on the server but some secrets are missing locally.
    /// The user needs to provide their recovery key to finish setup.
    Incomplete,
}

impl From<SdkRecoveryState> for RecoveryState {
    fn from(state: SdkRecoveryState) -> Self {
        match state {
            SdkRecoveryState::Unknown => Self::Unknown,
            SdkRecoveryState::Enabled => Self::Enabled,
            SdkRecoveryState::Disabled => Self::Disabled,
            SdkRecoveryState::Incomplete => Self::Incomplete,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn state_conversion_covers_all_variants() {
        assert_eq!(RecoveryState::from(SdkRecoveryState::Unknown), RecoveryState::Unknown);
        assert_eq!(RecoveryState::from(SdkRecoveryState::Enabled), RecoveryState::Enabled);
        assert_eq!(RecoveryState::from(SdkRecoveryState::Disabled), RecoveryState::Disabled);
        assert_eq!(RecoveryState::from(SdkRecoveryState::Incomplete), RecoveryState::Incomplete);
    }
}
