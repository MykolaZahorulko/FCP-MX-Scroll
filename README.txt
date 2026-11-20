================================================================================
FCP-MX-Scroll (v2.1.0)
Ultra-Lightweight Final Cut Pro Scroll & Timeline Helper for Logitech MX Master 3S
================================================================================

OVERVIEW
--------
FCP-MX-Scroll is a minimal native macOS menu-bar utility (LSUIElement = true,
no Dock icon, near-zero CPU/RAM usage) that activates ONLY when Final Cut Pro
(com.apple.FinalCut / com.apple.FinalCutApp) is the frontmost application.
In all other apps, all mouse, scroll, and keyboard events pass through untouched.

CORE FEATURES (Final Cut Pro Frontmost)
---------------------------------------
1. Default Wheel Mapping ("Swap Main & Side Wheels" OFF):
   - Modifier + Main (Vertical) Wheel Up / Down
     -> Timeline Zoom In / Out (Command + = / Command + -)
   - Modifier + Side (Horizontal Thumb) Wheel Right/Up or Left/Down
     -> Clip Height Increase / Decrease (Command + Shift + = / Command + Shift + -)

2. Swapped Wheel Mapping ("Swap Main & Side Wheels" ON):
   - Modifier + Main (Vertical) Wheel -> Clip Height (Command + Shift + = / -)
   - Modifier + Side (Thumb) Wheel    -> Timeline Zoom (Command + = / Command + -)

3. Logic Pro Style Return / Enter -> Jump to Start of Timeline:
   - Toggleable via "Jump to Start on Return / Enter (Logic Pro style)"
   - Pressing Return (keyCode 36) or Keypad Enter (keyCode 76) with no modifiers
     sends Fn + Left Arrow (Home, keyCode 115) to jump the playhead to the start.
   - Collision-safe: Automatically disabled when typing in text fields, title
     editors, search boxes, inspector inputs, renaming clips, or in modal dialogs.

MENU BAR ICON & COMPACT SETTINGS POPOVER
----------------------------------------
Click the mouse icon in the top-right macOS menu bar to configure:
  - Master Enable / Disable switch
  - Live Accessibility Status Indicator ("Granted" / "Not Granted") + Reload button
  - Compact Trigger Modifier Dropdown: Option (⌥), Control (⌃), Command (⌘), Shift (⇧)
  - Swap Main & Side Wheels toggle + individual Invert checkboxes
  - Independent Main Wheel & Side Wheel Sensitivity sliders (1.0 - 10.0)
  - Jump to Start on Return / Enter checkbox
  - Launch at Login toggle (SMAppService) + Reset & Quit buttons
================================================================================
