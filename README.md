# dGPU Sleep Monitor
![alt text](<screenshots/Screenshot from 2026-06-08 00-49-48.png>)
![alt text](<screenshots/Screenshot from 2026-06-08 00-50-01.png>)

A [Dank Material Shell](https://github.com/AvengeMedia/DankMaterialShell) / Quickshell plugin that monitors your discrete GPU power state and optionally displays battery wattage alongside mode-switching controls for [superggfxctl](https://gitlab.com/asus-linux/supergfxctl) and [cardwire](https://opengamingcollective.github.io/cardwire/).


## Features

- **DGPU power state monitoring** — reads PCI `power_state` from sysfs (`D0`, `D3cold`, `D3hot`, `D3ci`, etc.)
- **Runtime PM status display** — shows kernel runtime power management status (`active` / `suspended`)
- **Power control setting** — displays current PCIe power control configuration
- **Battery wattage** — real-time power draw from all detected batteries (optional, toggleable)
- **GPU mode switching** — integrated buttons for supergfxctl and cardwire in the popout panel (optional, toggleable)
- **Configurable refresh interval** — adjust how often battery data is polled (1–30 seconds)
- **Custom PCI address** — works with any dGPU; configure your device's PCI address in settings

## Installation

### Prerequisites

Install at least one GPU mode management tool (the widget gracefully hides sections for tools that aren't installed):

| Tool | Purpose | Install |
|------|---------|---------|
| [supergfxctl](https://gitlab.com/asus-linux/supergfxctl) | NVIDIA dGPU mode switching on Linux | Arch: `pacman -S supergfxctl` · Fedora: via COPR · Other: build from source |
| [cardwire](https://opengamingcollective.github.io/cardwire/) | Alternative GPU mode switcher | Arch: AUR (`cardwire-git`) · Build from source |

### Plugin Setup

1. Clone this repository into your Quickshell/DMS plugin directory:
   ```bash
   mkdir -p ~/.config/Quickshell/plugins
   git clone https://github.com/xantrk/dgpu-sleep-monitor.git ~/.config/Quickshell/plugins/dgpu-sleep-monitor
   ```

2. Restart Quickshell / Dank Material Shell.

3. Add the widget to your bar configuration and point it at the plugin component:
   ```yaml
   # Example for Dank Material Shell bar config
   widgets:
     - type: PluginComponent
       pluginId: dgpuStatus
       settings:
         showBattery: true        # Show battery wattage in the pill
         refreshInterval: 5       # Poll interval in seconds
         showSupergfxctl: true    # Show supergfxctl mode buttons
         showCardwire: true       # Show cardwire mode buttons
   ```

## Configuration

Open the widget's settings panel from your bar to adjust these options:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `showBattery` | Toggle | `true` | Display battery wattage in the bar pill |
| `refreshInterval` | Slider (1–30s) | `5` | How often to poll battery data |
| `showSupergfxctl` | Toggle | `true` | Show supergfxctl mode toggle buttons |
| `showCardwire` | Toggle | `true` | Show cardwire mode toggle buttons |
| `pciAddress` | Text field | `02:00.0` | Your dGPU PCI address — find it with `lspci \| grep -i vga` |

## How It Works

### DGPU Power States

The plugin reads the PCIe power state from `/sys/bus/pci/devices/0000:<pciAddr>/power_state`:

| State | Meaning | Color |
|-------|---------|-------|
| `D3cold` | Fully suspended, no GPU context preserved | Green — idle |
| `D3` | Suspended | Green — idle |
| `D0` | Fully active, drawing full power | Orange/Red — active |

### Battery Wattage

Reads `/sys/class/power_supply/BAT*/power_now` (or falls back to `voltage_now × current_now`) across all detected batteries, sums the values, and displays the absolute wattage in the bar pill.

### AC / Charging Status

Detects AC adapter presence via `/sys/class/power_supply/ADP*/online` or `/sys/class/power_supply/IEC*/online`, combined with battery status from `BAT*/status`.

## Troubleshooting

**Widget shows "N/A" for GPU state:**
- Verify your PCI address is correct: `lspci | grep -i vga` → look for the discrete GPU entry and extract the address portion (e.g., `02:00.0`). Set it in settings.
- Check that the sysfs path exists: `cat /sys/bus/pci/devices/0000:<your-address>/power_state`

**Battery wattage not showing:**
- Ensure at least one battery is detected: `ls /sys/class/power_supply/BAT*`
- The script exits with code 1 and displays "N/A" when no batteries are found — this is normal on desktops.

**supergfxctl/cardwire buttons missing from popout:**
- Verify the tool is installed and runnable: `supergfxctl -g` or `cardwire get`
- Toggle the corresponding setting (`showSupergfxctl` / `showCardwire`) in the widget settings panel.

**Stale data not refreshing:**
- The GPU state and runtime status refresh every 5 seconds. Battery wattage follows your configured `refreshInterval`. Adjust these in settings if needed.
