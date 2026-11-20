# FCP-MX-Scroll

Ultra-lightweight native macOS menu-bar utility (`LSUIElement = true`, near-zero CPU/RAM usage) tailored for **Final Cut Pro** (`com.apple.FinalCut` / `com.apple.FinalCutApp`) and the **Logitech MX Master 3S** mouse.

Intercepts modified scroll-wheel events and optional timeline navigation keys **only when Final Cut Pro is the active frontmost application**. In all other apps (Logic Pro, browsers, Finder, etc.), all mouse, scroll, and keyboard events pass through completely untouched.

---

## Features

### 1. MX Master 3S Dual-Wheel Mapping (Final Cut Pro Only)
Hold your chosen trigger modifier (`Option ⌥` by default) while scrolling in Final Cut Pro:

| Mode | Main MagSpeed Wheel (Vertical) | Side Thumb Wheel (Horizontal) |
| :--- | :--- | :--- |
| **Default (`Swap Wheels` OFF)** | **Timeline Zoom** (`⌘=` / `⌘-`) | **Clip Height** (`⇧⌘=` / `⇧⌘-`) |
| **Swapped (`Swap Wheels` ON)** | **Clip Height** (`⇧⌘=` / `⇧⌘-`) | **Timeline Zoom** (`⌘=` / `⌘-`) |

- **High-Resolution MX Master 3S Delta Engine**: Normalizes `scrollWheelEventPointDeltaAxis1/2`, `scrollWheelEventFixedPtDeltaAxis1/2`, and `scrollWheelEventDeltaAxis1/2` into unified point units so both Logi Options+ smooth scrolling and discrete ratchet notches respond with crisp, single-notch accuracy and zero double-stepping.
- **Full Event Consumption**: Modified scroll events are consumed in Final Cut Pro so the timeline never scrolls while zooming or resizing clip height.

### 2. Logic Pro Style `Return / Enter` → Jump to Start of Timeline
- Optional checkbox: **"Jump to Start on Return / Enter (Logic Pro style)"**.
- When enabled and Final Cut Pro is frontmost, pressing `Return` (`keyCode 36`) or `Keypad Enter` (`keyCode 76`) without modifiers sends `Fn + Left Arrow` (`Home`, `keyCode 115`) to move the playhead to the start of the timeline.
- **Collision-Safe (`TextInputCollisionGuard`)**: Inspects macOS Accessibility focus (`AXFocusedUIElement`, `AXFocusedWindow`, `AXRole`, `AXEditable`, `AXSelectedTextRange`) and automatically passes `Return` / `Enter` through untouched whenever you are typing in a text field, title editor, search box, inspector field, renaming a clip, or interacting with a modal dialog.

### 3. Compact Native Menu Bar UI
Click the mouse icon in the macOS top menu bar to configure:
- **Master Enable / Disable Switch**
- **Live Accessibility Status Indicator** (`Granted` / `Not Granted`) with one-click **Grant Access / Reload Tap**
- **Trigger Modifier Dropdown**: `Option (⌥)`, `Control (⌃)`, `Command (⌘)`, or `Shift (⇧)`
- **Swap Main & Side Wheels Toggle** + per-wheel **Invert** direction checkboxes
- **Independent Main Wheel & Side Wheel Sensitivity Sliders** (`1.0 – 10.0`)
- **Jump to Start on Return / Enter Toggle**
- **Launch at Login Toggle** (powered by native `SMAppService.mainApp`)

---

## Installation

1. Download **`FCP-MX-Scroll.dmg`** from the latest release (or build from source below).
2. Open `FCP-MX-Scroll.dmg` and drag **`FCP-MX-Scroll.app`** into **`/Applications`**.
3. Launch **`/Applications/FCP-MX-Scroll.app`**.
4. Click the mouse icon in the top-right macOS menu bar → click **`Grant Access`** → enable **`FCP-MX-Scroll`** in **System Settings → Privacy & Security → Accessibility**.

> **Logi Options+ Note:** Keep your MX Master 3S Horizontal Thumb Wheel set to standard **"Horizontal scroll"** in Logi Options+ so macOS CoreGraphics (`CGEventTap`) receives horizontal `Axis 2` scroll events cleanly.

---

## Building from Source

Requires macOS 13.0+ and Xcode Command Line Tools (`swiftc`):

```zsh
./build.sh
```

This compiles `FCP-MX-Scroll.app`, ad-hoc signs it with bundle identifier `com.mriynick.FCP-MX-Scroll`, and generates `FCP-MX-Scroll.dmg`.
