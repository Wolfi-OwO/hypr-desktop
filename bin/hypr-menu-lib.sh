#!/usr/bin/env bash
# Shared rofi invocation for all the waybar dropdowns.
#
# GNOME-like pointer behaviour:
#   -hover-select                  highlight the row under the cursor
#   -me-select-entry ''            do NOT require a click just to select
#   -me-accept-entry MousePrimary  a single left click runs the row
# Without these, rofi needs a click to select and a second click (or Enter)
# to activate, which is what made the menus feel unresponsive.
# -click-to-exit is rofi's default but is stated explicitly here so a stray
# rofi config or theme cannot turn it off: clicking anywhere outside the
# dropdown dismisses it.
ROFI_UX=(-hover-select -me-select-entry '' -me-accept-entry MousePrimary -click-to-exit)

rofi_left()  { rofi -dmenu -i "${ROFI_UX[@]}" -theme "$HOME/.config/rofi/dropdown-left.rasi"  -p "$1"; }
rofi_right() { rofi -dmenu -i "${ROFI_UX[@]}" -theme "$HOME/.config/rofi/dropdown-right.rasi" -p "$1"; }
