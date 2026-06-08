import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "dgpuStatus"

    StyledText {
        width: parent.width
        text: "Power Status Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Configure which metrics to display in the bar."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "showBattery"
        label: "Show Battery Wattage"
        description: "Display real-time power consumption in the bar widget"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "refreshInterval"
        label: "Refresh Interval"
        description: "How often to update battery wattage (in seconds)"
        defaultValue: 5
        minimum: 1
        maximum: 30
        unit: "s"
        leftIcon: "schedule"
    }

    StyledText {
        width: parent.width
        text: "GPU Mode Toggles"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceVariantText
    }

    ToggleSetting {
        settingKey: "showSupergfxctl"
        label: "Show supergfxctl in Popout"
        description: "Display GPU mode toggle buttons from supergfxctl in the widget popout"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showCardwire"
        label: "Show cardwire in Popout"
        description: "Display GPU mode toggle buttons from cardwire in the widget popout"
        defaultValue: true
    }

    StyledText {
        width: parent.width
        text: "PCI Configuration"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceVariantText
    }

    StringSetting {
        settingKey: "pciAddress"
        label: "PCI Device Address"
        description: "Find yours with: lspci | grep -i vga"
        placeholder: "02:00.0"
        defaultValue: "02:00.0"
    }
}
