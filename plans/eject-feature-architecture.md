# Eject Feature - Architecture

## Overview

This document describes the architecture for the volume eject feature in BetterFinder.

## Implementation Details

### VolumeService

The `VolumeService` class handles all volume-related operations:

- **Mount Point Resolution**: `resolveVolumeMountPoint(for:)` identifies the correct mount point for a given URL by filtering mounted volumes and matching the longest prefix. It excludes `/` and `/Volumes` from candidates and ensures proper path boundary matching (trailing slash or exact match).

- **Ejectability Check**: `isEjectableVolumeAsync(_:)` determines if a volume can be ejected by checking `volumeIsRemovable`, `volumeIsLocal`, and `volumeIsRootFileSystem` resource keys, plus detecting external drives under `/Volumes/`.

- **Eject Sequence**: `ejectVolume(at:)` performs the following:
  1. Resolves the mount point
  2. Validates ejectability
  3. Executes `diskutil eject <mountPath>` as primary action
  4. Falls back to `diskutil unmount <mountPath>` if eject fails

### UI Integration

- **SidebarView**: Displays an eject button (`eject.fill` SF Symbol) next to ejectable volumes in the Locations section. The button uses localized strings (`EJECT_VOLUME_TOOLTIP`, `EJECT_BUTTON`) for accessibility.

- **BrowserState**: Maintains a cached `currentVolumeIsEjectable` value that is refreshed asynchronously when navigating. The refresh task is cancellable and validates that `currentVolumeURL` hasn't changed before updating the cache.

### AppState Coordination

- `AppState` owns the `VolumeService` singleton
- `ejectVolume(for:)` wraps the async call and handles UI refresh + error presentation
- After successful eject, tree roots are rebuilt and both browsers are refreshed

## Error Handling

All eject errors are wrapped in `VolumeError` enum with localized descriptions:
- `.notEjectable` - Volume cannot be ejected
- `.mountPointNotFound` - No mount point found for URL
- `.unmountFailed(String)` - diskutil command failed with error message

## Testing

Unit tests in `BrowserVolumeTests` verify:
- Mount point resolution returns `nil` for `/`, `/Volumes`, and non-volume paths
- Mount point resolution correctly identifies volumes under `/Volumes/*`
- Prefix collision handling (e.g., `/Volumes/Data` vs `/Volumes/DataBackup`)
- `BrowserState.currentVolumeURL` returns `nil` for non-volume paths