---
description: Test the Parlotte macOS app UI using osascript accessibility APIs and screenshots — without requiring computer-use MCP or Xcode UI tests
match:
  - test ui
  - test the app
  - test visually
  - check the app
  - verify the ui
  - feedback loop
  - test scroll
  - test pagination
  - launch the app
---

# UI Testing via Accessibility APIs

The Parlotte macOS app is built with Swift Package Manager (not Xcode), so it runs as a bare binary without a `.app` bundle. This means computer-use MCP cannot target it. Instead, use macOS Accessibility APIs via `osascript` (AppleScript) and `screencapture` for visual verification.

## Prerequisites

The user must have macOS Accessibility permissions enabled for the terminal/IDE running Claude Code (System Settings > Privacy & Security > Accessibility).

## Fast Accessibility Inspector (`ax-inspect`)

A compiled Swift tool at `.claude/skills/ax-inspect` provides 10x faster UI inspection than osascript. Compile once, then use:

```bash
# Compile (only needed once after editing the source)
swiftc .claude/skills/ax-inspect.swift -o .claude/skills/ax-inspect -framework AppKit -framework ApplicationServices

# Commands:
.claude/skills/ax-inspect dump                          # All text elements
.claude/skills/ax-inspect first 15                      # First N text elements
.claude/skills/ax-inspect find "Load older"             # Search for text
.claude/skills/ax-inspect click-button 700 270 1400 310 # Click button in coordinate range
.claude/skills/ax-inspect select "Alerts"               # Select a room by name
```

**Prefer `ax-inspect` over `osascript` for all UI inspection.** It runs in ~0.4s vs 5-10s for osascript. The osascript examples below are kept as reference but should only be used as fallback.

## Launching the App

```bash
cd /Users/matthieugouel/Documents/Code/parlotte/apple/Parlotte && swift run Parlotte 2>&1 &
```

Run this in background. The app retains session state, so if the user was previously logged in, it will restore the session automatically. If not, the user will need to authenticate manually (especially for OAuth/SSO flows).

## Core Accessibility Commands

All commands use `osascript` with `dangerouslyDisableSandbox: true`.

### Check if the app is running

```bash
pgrep -la Parlotte
```

### Get the full UI element tree (roles and values)

This is the primary inspection tool. It dumps every visible UI element:

```bash
osascript -e '
tell application "System Events"
    tell process "Parlotte"
        tell window 1
            set allElems to entire contents
            set output to ""
            repeat with e in allElems
                try
                    set r to role of e
                    set v to value of e
                    if v is not missing value and v is not "" then
                        set output to output & r & ": " & v & linefeed
                    end if
                end try
            end repeat
            return output
        end tell
    end tell
end tell'
```

### Select a room from the sidebar

SwiftUI List rows need `set selected of e to true`, not `click`:

```bash
osascript -e '
tell application "System Events"
    tell process "Parlotte"
        tell window 1
            set allElems to entire contents
            repeat with e in allElems
                try
                    if role of e is "AXRow" then
                        set rowContents to entire contents of e
                        repeat with rc in rowContents
                            try
                                if role of rc is "AXStaticText" and value of rc is "ROOM_NAME_HERE" then
                                    set selected of e to true
                                    return "selected"
                                end if
                            end try
                        end repeat
                    end if
                end try
            end repeat
            return "not found"
        end tell
    end tell
end tell'
```

Replace `ROOM_NAME_HERE` with the actual room name (e.g., "Alerts", "General").

### Scrolling the message list

**Important:** The message list uses an `NSScrollView` wrapped in `NSViewRepresentable`. Its scrollbar may NOT be exposed through accessibility (the only accessible scrollbar is the sidebar's). Instead, verify scroll state by checking which messages are visible in the UI tree.

To check visible messages after an action, dump the first N text elements (items 7+ skip the header):

```bash
osascript -e '
tell application "System Events"
    tell process "Parlotte"
        tell window 1
            set allElems to entire contents
            set texts to {}
            repeat with e in allElems
                try
                    if role of e is "AXStaticText" and value of e is not missing value and value of e is not "" then
                        set end of texts to value of e
                    end if
                end try
            end repeat
            set cnt to count of texts
            set output to "total: " & cnt & linefeed
            -- Items 1-6 are header (room name, user, server, room list)
            -- Items 7+ are message content
            set maxShow to 15
            if cnt < maxShow then set maxShow to cnt
            repeat with i from 7 to maxShow
                set output to output & i & ": " & item i of texts & linefeed
            end repeat
            return output
        end tell
    end tell
end tell'
```

**Note:** Accessibility may only report elements near the viewport, not the full list. The total count can vary based on scroll position.

### Search for a specific text in the UI

Useful for checking if a button label or message exists:

```bash
osascript -e '
tell application "System Events"
    tell process "Parlotte"
        tell window 1
            set allElems to entire contents
            repeat with e in allElems
                try
                    set v to value of e
                    if v is not missing value and v contains "SEARCH_TEXT" then
                        return "FOUND: " & v
                    end if
                end try
            end repeat
            return "Not found"
        end tell
    end tell
end tell'
```

### Click "Load older messages" button

The "Load older messages" button is a SwiftUI `Button` with `.plain` style. It does NOT appear as `AXStaticText` — it is an `AXButton` without an accessible label. It sits at the top of the message area. To click it, find buttons by position: the button is horizontally centered in the message area, near the top (y around 280-310, x around 1100-1300 depending on window position).

```bash
osascript -e '
tell application "System Events"
    tell process "Parlotte"
        tell window 1
            -- Get window position to calculate relative coords
            set winPos to position of window 1
            -- The button is in the message area, centered horizontally, near top
            set allElems to entire contents
            repeat with e in allElems
                try
                    if role of e is "AXButton" then
                        set p to position of e
                        -- Message area: x > 700, y between 270-310
                        if (item 1 of p) > 700 and (item 1 of p) < 1400 and (item 2 of p) > 270 and (item 2 of p) < 310 then
                            click e
                            return "clicked button at " & (item 1 of p) & "," & (item 2 of p)
                        end if
                    end if
                end try
            end repeat
            return "no matching button found"
        end tell
    end tell
end tell'
```

**Note:** The position range depends on window location and size. If the window has moved, adjust the coordinate ranges. Get the window position first with:

```bash
osascript -e '
tell application "System Events"
    tell process "Parlotte"
        return {position of window 1, size of window 1}
    end tell
end tell'
```

### Click a button by searching for text

Some buttons have text children that can be found. This works for buttons with visible labels:

```bash
osascript -e '
tell application "System Events"
    tell process "Parlotte"
        tell window 1
            set allElems to entire contents
            repeat with e in allElems
                try
                    if role of e is "AXStaticText" and value of e is "Button Label Here" then
                        click e
                        return "clicked"
                    end if
                end try
            end repeat
            return "not found"
        end tell
    end tell
end tell'
```

### Set a text field value (e.g., login form)

```bash
osascript -e '
tell application "System Events"
    tell process "Parlotte"
        tell group 1 of window 1
            set value of text field 1 to "https://matrix.nxthdr.dev"
        end tell
    end tell
end tell'
```

## Taking Screenshots

Use `screencapture` to take a screenshot, then `Read` to view it:

```bash
screencapture -x $TMPDIR/parlotte_screenshot.png
```

Then use the Read tool on the resulting file to view it. The `-x` flag suppresses the shutter sound.

## Typical Testing Workflow

1. **Build**: `cd apple/Parlotte && swift build`
2. **Launch**: `swift run Parlotte` (in background)
3. **Wait**: A few seconds for the app to load
4. **Inspect**: Dump UI tree to see current state
5. **Navigate**: Select a room via the row selection command
6. **Wait**: A few seconds for messages to load
7. **Verify**: Search for specific text, check scroll position, take screenshot
8. **Interact**: Scroll up/down, click buttons
9. **Re-verify**: Check state after interaction

## Rebuilding and Relaunching

After code changes, kill the old instance and relaunch:

```bash
kill $(pgrep Parlotte) 2>/dev/null
cd /Users/matthieugouel/Documents/Code/parlotte/apple/Parlotte && swift build 2>&1
# Then relaunch
swift run Parlotte 2>&1 &
```

If Rust code changed, rebuild the XCFramework first:

```bash
./scripts/build-apple.sh
```

## Limitations

- **OAuth/SSO login**: Cannot be automated — requires user interaction in the browser
- **SwiftUI accessibility**: Some elements may not have accessible names/labels. Use position or parent-child traversal as fallback
- **Timing**: After selecting a room or triggering an action, wait 2-3 seconds before inspecting. Run inspection commands with `run_in_background: true` if needed
- **Long commands**: osascript that traverses the full UI tree can take a few seconds for rooms with many messages
