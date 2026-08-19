#!/usr/bin/env python3
"""Deposit Turbo tray applet (optional component, installed via `aqa install turbo`).

Lives in the top-right tray. Click to toggle "turbo" (max CPU/GPU). When turbo
is enabled, a spinning wheel appears and *gradually fades away*; when disabled
the spinner stops and the icon returns to the normal state.

Requires: python3-gi, gir1.2-gtk-3.0, gir1.2-appindicator3-0.1
"""
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("AppIndicator3", "0.1")
from gi.repository import Gtk, AppIndicator3, GLib

import os
import subprocess

STATE_FILE = "/var/lib/deposit-turbo/state"
TURBO_ICON = "deposit-turbo"   # rounded brand icon (see components/turbo)
FALLBACK_ICON = "gtk-yes"


def set_icon(name):
    try:
        ind.set_icon(name)
        return True
    except Exception:
        return False


def turbo_state():
    try:
        return open(STATE_FILE).read().strip()
    except Exception:
        return "off"


def set_state():
    return subprocess.run(["deposit-turbo", "toggle"], check=False)


def show_spinner():
    """A spinner window that fades in then gradually disappears."""
    win = Gtk.Window(title="Deposit Turbo")
    win.set_decorated(False)
    win.set_keep_above(True)
    win.set_default_size(80, 80)
    spinner = Gtk.Spinner()
    spinner.start()
    win.add(spinner)
    win.set_position(Gtk.WindowPosition.CENTER)
    win.show_all()
    # fade in quickly, then fade out slowly and destroy
    for i in range(1, 11):
        win.set_opacity(i / 10.0)
        win.present()
        GLib.usleep(60_000)
    for i in range(10, 0, -1):
        win.set_opacity(i / 10.0)
        win.present()
        GLib.usleep(120_000)
    win.destroy()


def on_toggle(_):
    was = turbo_state()
    set_state()
    if was != "on":  # we just turned it ON
        GLib.idle_add(show_spinner)
    refresh_icon()


def refresh_icon():
    s = turbo_state()
    set_icon(TURBO_ICON if s == "on" else FALLBACK_ICON)
    return True


ind = AppIndicator3.Indicator.new(
    "deposit-turbo", FALLBACK_ICON, AppIndicator3.IndicatorCategory.APPLICATION_STATUS
)
ind.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
ind.set_title("Deposit Turbo")
# prefer the rounded brand icon if present
if not set_icon(TURBO_ICON):
    set_icon(FALLBACK_ICON)

menu = Gtk.Menu()
item = Gtk.MenuItem.new_with_label("Toggle Turbo (Alt+K)")
item.connect("activate", on_toggle)
menu.append(item)
sep = Gtk.SeparatorMenuItem()
menu.append(sep)
quit_item = Gtk.MenuItem.new_with_label("Quit")
quit_item.connect("activate", Gtk.main_quit)
menu.append(quit_item)
menu.show_all()
ind.set_menu(menu)

GLib.timeout_add_seconds(2, refresh_icon)
Gtk.main()
