import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var popoutService: null

    // --- Battery Wattage ---
    property string batteryWattage: "..."
    property int refreshInterval: (pluginData.refreshInterval || 5) * 1000
    property bool showBattery: pluginData.showBattery ?? true
    property bool showSupergfxctl: pluginData.showSupergfxctl ?? true
    property bool showCardwire: pluginData.showCardwire ?? true
    property bool hasBattery: false

    // --- DGPU Power State ---
    property string dgpuState: "..."
    readonly property string pciAddr: pluginData.pciAddress || "02:00.0"

    function getPciPath() { return `/sys/bus/pci/devices/0000:${root.pciAddr}/power_state` }
    function getGpuPowerPath(attr) { return `/sys/bus/pci/devices/0000:${root.pciAddr}/power/${attr}` }

    // --- GPU sysfs power attributes ---
    property string gpuRuntimeStatus: "..."
    property string gpuPowerControl: "..."

    // --- Battery capacity info from sysfs ---
    property int batteryCapacityPct: 0
    property real batteryDesignWh: 0
    property real batteryCurrentWh: 0

    // Robust health calculation helper
    readonly property int batteryHealthPct: {
        if (root.batteryDesignWh <= 0 || root.batteryCurrentWh <= 0) return -1
        return Math.min(100, Math.round((root.batteryCurrentWh / root.batteryDesignWh) * 100))
    }

    // --- Command Availability (updated on each process exit) ---
    property bool supergfxctlAvailable: true
    property bool cardwireAvailable: true

    // --- Mode States (read from commands) ---
    property string supergfxctlMode: "Unknown"
    property var supportedSupergfxctlModes: ["Integrated", "Hybrid", "Performance"]
    property string cardwireMode: "unknown"
    property var supportedCardwireModes: ["integrated", "hybrid"]

    // --- Theme-based Colors ---
    readonly property color greenOk: Theme.success
    readonly property color redWarn: Theme.error
    readonly property color mutedText: Theme.surfaceVariantText
    readonly property color modeHybrid: Theme.warning

    // --- GPU Color Logic ---
    // Green = Suspended | Orange = Active on AC | Red = Active on Battery
    readonly property color dgpuColor: {
        const state = dgpuState.trim()
        if (state === "D3cold" || state === "D3") {
            return Theme.surfaceText
        } else if (state === "D0" || state === "D3ci" || state === "D0i") {
            return root.onBattery ? root.redWarn : Theme.surfaceText
        } else {
            return Theme.surfaceText
        }
    }

   readonly property string gpuIconName: {
       const state = dgpuState.trim()
       if (state === "D3cold" || state === "D3" || state === "D3Cold") {
           return "eco"
       } else {
           return "speed"
       }
   }

   // --- Mode color helper ---
    function modeColor(mode) {
        const lower = mode.toLowerCase().trim()
        if (lower === "integrated" || lower === "int.")
            return root.greenOk
        else if (lower === "hybrid")
            return root.modeHybrid
        else
            return root.redWarn
    }

   // --- AC adapter / battery charging status from sysfs ---
    property string acOnline: "..."       // 1 = plugged in, 0 = unplugged
    property string batStatus: "..."      // Charging / Discharging / Full / Not charging

    readonly property bool isOnACPower: root.acOnline === "1"
    readonly property bool onBattery: !root.isOnACPower && root.batStatus !== "Full"

    // --- Dynamic battery icon ---
    readonly property string batteryIconName: {
        if (!hasBattery) return "battery_unknown"
        if (root.isOnACPower || root.batStatus === "Charging" || root.batStatus === "Full") {
            return "battery_charging_full"
        }
        return "battery_6_bar"
    }

    // --- Battery icon color ---
    readonly property color batteryIconColor: {
        if (!root.hasBattery) return Theme.surfaceTextMedium
        if (root.isOnACPower || root.batStatus === "Charging" || root.batStatus === "Full") return Theme.primary
        if (root.batStatus === "Discharging") return parseFloat(batteryWattage) < 10 ? Theme.warning : Theme.surfaceText
        return Theme.surfaceText
    }

    // --- Battery header text helper ---
    readonly property string batteryChargeLabel: {
        if (!hasBattery) return ""
        if (root.isOnACPower && root.batStatus === "Full") return "Fully charged · AC Connected"
        if (root.isOnACPower) return "Charging · AC Connected"
        if (root.batStatus === "Charging") return "Charging"
        if (root.batStatus === "Discharging") return "Discharging"
        if (root.batStatus === "Full") return "Fully charged"
        return ""
    }
    readonly property string batteryChargeColor: {
        if (!hasBattery) return "transparent"
        if (root.isOnACPower || root.batStatus === "Charging" || root.batStatus === "Full") return Theme.primary
        if (root.batStatus === "Discharging") return Theme.surfaceTextMedium
        return "transparent"
    }

    // --- DGPU state display text (fixed-width) ---
    readonly property string fixedDgpuDisplay: {
        switch (dgpuState) {
        case "D0":  return "D0   "
        case "D3cold": return "D3cold"
        case "D3":  return "D3   "
        case "D3Hot": return "D3Hot "
        case "D3ci": return "D3ci  "
        default:    return dgpuState.padEnd(8, " ")
        }
    }

    // --- Process: Battery Wattage ---
    Process {
        id: powerProcess
        command: ["sh", Qt.resolvedUrl("get-power-usage.sh").toString().replace("file://", "")]
        running: false

        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                root.batteryWattage = trimmed
                root.hasBattery = (trimmed !== "N/A" && trimmed.length > 0)
            }
        }

        onExited: code => {
            if (code === 1) root.hasBattery = false
        }
    }

  // --- Process: AC Adapter + Battery Status ---
    Process {
        id: batteryStatusProcess
        command: ["sh", Qt.resolvedUrl("get-battery-status.sh").toString().replace("file://", "")]
        running: false

        // Handles split structures elegantly on both space-separated and line-separated outputs
        stdout: SplitParser {
            id: batteryStatusParser
            property int index: 0
            onRead: line => {
                const trimmed = line.trim()
                if (trimmed.length === 0) return
                const parts = trimmed.split(/\s+/)
                if (parts.length >= 2) {
                    root.acOnline = parts[0]
                    root.batStatus = parts[1]
                } else {
                    if (batteryStatusParser.index === 0) {
                        root.acOnline = trimmed
                    } else if (batteryStatusParser.index === 1) {
                        root.batStatus = trimmed
                    }
                    batteryStatusParser.index++
                }
            }
        }
        onExited: { batteryStatusParser.index = 0 }
    }

   // --- Process: DGPU Power State ---
    Process {
        id: dgpuProcess
        command: ["cat", root.getPciPath()]
        running: false

        stdout: SplitParser {
            onRead: data => {
                const state = data.trim()
                if (state.length > 0) root.dgpuState = state
            }
        }
    }

    // --- Process: GPU runtime_status + power_control ---
    Process {
        id: gpuPowerStatus
        command: ["sh", "-c", `cat "${root.getGpuPowerPath("runtime_status")}" 2>/dev/null; echo '---'; cat "${root.getGpuPowerPath("control")}" 2>/dev/null`]
        running: false

        stdout: SplitParser {
            id: gpuPowerParser
            property int fieldIndex: 0

            onRead: line => {
                const trimmed = line.trim()
                if (trimmed === "---") {
                    gpuPowerParser.fieldIndex++
                    return
                }
                if (gpuPowerParser.fieldIndex === 0) {
                    if (trimmed.length > 0) root.gpuRuntimeStatus = trimmed
                } else if (gpuPowerParser.fieldIndex === 1) {
                    if (trimmed.length > 0) root.gpuPowerControl = trimmed
                }
            }
        }

        onExited: { 
            gpuPowerParser.fieldIndex = 0 // Safely reset parsing steps without clobbering final outputs
        }
    }

   // --- Process: Battery capacity info from sysfs ---
    Process {
        id: batteryCapacityProcess
        command: ["sh", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1; echo '---'; cat /sys/class/power_supply/BAT*/energy_full_design 2>/dev/null | head -1; echo '---'; cat /sys/class/power_supply/BAT*/energy_full 2>/dev/null | head -1"]
        running: false

        stdout: SplitParser {
            id: batteryCapacityParser
            property int fieldIndex: 0
            onRead: line => {
                const trimmed = line.trim()
                if (trimmed === "---") {
                    batteryCapacityParser.fieldIndex++
                    return
                }
                const val = parseFloat(trimmed)
                if (isNaN(val)) return
                if (batteryCapacityParser.fieldIndex === 0) root.batteryCapacityPct = Math.round(val)
                else if (batteryCapacityParser.fieldIndex === 1) root.batteryDesignWh = val / 1e6
                else if (batteryCapacityParser.fieldIndex === 2) {
                    root.batteryCurrentWh = val / 1e6
                    if (root.batteryDesignWh > 0 && root.batteryCurrentWh > root.batteryDesignWh)
                        root.batteryDesignWh = root.batteryCurrentWh
                }
            }
        }

        onExited: { batteryCapacityParser.fieldIndex = 0 }
    }

    // --- Process: Read supergfxctl mode ---
    Process {
        id: supergfxctlGet
        command: ["supergfxctl", "-g"]
        running: false
        stdout: SplitParser {
            onRead: data => { root.supergfxctlMode = data.trim() }
        }
        onExited: code => { root.supergfxctlAvailable = (code === 0) }
    }

    // --- Process: Read cardwire mode ---
    Process {
        id: cardwireGet
        command: ["cardwire", "get"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim()
                let match = line.match(/current\s+mode:\s*(\S+)/i)
                if (match && match[1]) {
                    root.cardwireMode = match[1].toLowerCase()
                    return
                }
                if (line.length > 0 &&
                    !line.startsWith("Current") &&
                    !line.startsWith("Available")) {
                    root.cardwireMode = line.toLowerCase()
                }
            }
        }
        onExited: code => { root.cardwireAvailable = (code === 0) }
    }

    // --- Process: List supergfxctl supported modes ---
    Process {
        id: supergfxctlList
        command: ["supergfxctl", "-s"]
        running: false
        stdout: SplitParser {
            onRead: line => {
                var clean = line.replace(/[\[\]']/g, "").trim()
                if (clean.length > 0) {
                    root.supportedSupergfxctlModes = clean.split(/,\s*/)
                }
            }
        }
        onExited: code => { if (code !== 0) root.supergfxctlAvailable = false }
    }

    // --- Mode Switch Processes ---
    Process {
        id: supergfxctlSet
        command: []
        onExited: { supergfxctlGet.running = true }
    }
    Process {
        id: cardwireSet
        command: []
        onExited: { cardwireGet.running = true }
    }

    // --- Timers ---
    Timer {
        interval: root.refreshInterval; running: true; repeat: true; triggeredOnStart: true
        onTriggered: powerProcess.running = true
    }
    Timer {
        interval: 5000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            dgpuProcess.running = true
            gpuPowerStatus.running = true
            batteryCapacityProcess.running = true
            batteryStatusProcess.running = true
        }
    }
    Timer {
        interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            supergfxctlGet.running = true
            supergfxctlList.running = true
            cardwireGet.running = true
        }
    }

    Component.onCompleted: {
        // No longer needed — supergfxctlList now runs on the 3s timer
    }

    // --- Mode Switching Functions ---
    function setSupergfxctlMode(mode) {
        if (mode === root.supergfxctlMode) return
        if (supergfxctlSet.running) return
        root.supergfxctlMode = mode
        supergfxctlSet.command = ["supergfxctl", "-m", mode]
        supergfxctlSet.running = true
    }

    function setCardwireMode(mode) {
        if (mode === root.cardwireMode) return
        if (cardwireSet.running) return
        root.cardwireMode = mode
        cardwireSet.command = ["cardwire", "set", mode]
        cardwireSet.running = true
    }

   // --- Bar Pills ---
    horizontalBarPill: Component {
        Row {
            id: contentRow; spacing: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter

            // DankIcon {
            //     name: root.hasBattery ? root.batteryIconName : "cpu"
            //     size: Theme.iconSizeSmall
            //     color: root.hasBattery
            //         ? (root.showBattery && root.hasBattery ? root.batteryIconColor : Theme.surfaceTextMedium)
            //         : root.dgpuColor
            //     anchors.verticalCenter: parent.verticalCenter
            // }

            DankIcon {
                name: root.gpuIconName
                size: Theme.iconSizeSmall
                color: root.dgpuColor
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: showBattery && hasBattery ? `${batteryWattage} W` : ""
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
                visible: showBattery && hasBattery
            }

            StyledText {
                text: "│"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Bold
                color: Theme.surfaceTextMedium
                anchors.verticalCenter: parent.verticalCenter
                visible: root.hasBattery && root.showBattery
            }

            StyledText {
                text: dgpuState !== "..." ? dgpuState : "N/A"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.dgpuColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            id: contentColV; spacing: Theme.spacingXS
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            DankIcon {
                name: root.hasBattery ? root.batteryIconName : "cpu"
                size: Theme.iconSizeSmall
                color: root.hasBattery
                    ? (root.showBattery && root.hasBattery ? root.batteryIconColor : Theme.surfaceTextMedium)
                    : root.dgpuColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: showBattery && hasBattery ? `${batteryWattage} W` : ""
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
                visible: showBattery && hasBattery
            }

            StyledText {
                text: dgpuState !== "..." ? dgpuState : "N/A"
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.dgpuColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

   popoutContent: Component {
        PopoutComponent {
            id: popup
            headerText: "Power Status"

            property bool sgfxVisible: true
            property bool cwVisible: true
            property string sgfxMode: ""
            property string cwMode: ""

            Connections {
                target: root
                function onShowSupergfxctlChanged() { popup.sgfxVisible = root.showSupergfxctl }
                function onShowCardwireChanged()    { popup.cwVisible = root.showCardwire }
                function onSupergfxctlModeChanged() { popup.sgfxMode = root.supergfxctlMode }
                function onCardwireModeChanged()    { popup.cwMode = root.cardwireMode }
            }

            Component.onCompleted: {
                popup.sgfxVisible = root.showSupergfxctl
                popup.cwVisible = root.showCardwire
                popup.sgfxMode = root.supergfxctlMode
                popup.cwMode = root.cardwireMode
            }

            Item {
                id: contentWrapper
                width: parent.width
                implicitHeight: mainCol.implicitHeight

                Column {
                    id: mainCol
                    width: parent.width
                    spacing: Theme.spacingM
                    anchors.top: parent.top

                    // ==========================================
                    // 1. BATTERY SECTION (Dynamic Power & Health)
                    // ==========================================
                    Column {
                        width: parent.width
                        spacing: Theme.spacingS

                        // Section Header Title
                        StyledText {
                            text: "Battery"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceTextMedium
                            leftPadding: Theme.spacingS
                        }

                        // Flat Header Row (No Surface BG)
                        Row {
                            width: parent.width
                            height: 48
                            spacing: Theme.spacingM

                            DankIcon {
                                name: root.batteryIconName
                                size: Theme.iconSizeLarge
                                color: root.batteryIconColor
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                spacing: 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Theme.iconSizeLarge - 32 - Theme.spacingM * 2

                                Row {
                                    spacing: Theme.spacingS

                                    StyledText {
                                        text: {
                                            if (!hasBattery) return "No Battery"
                                            return root.batteryCapacityPct > 0 ? `${root.batteryCapacityPct}%` : "Battery"
                                        }
                                        font.pixelSize: Theme.fontSizeXLarge
                                        font.weight: Font.Bold
                                        color: Theme.primary
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    visible: root.hasBattery
                                    text: root.batteryChargeLabel
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceTextMedium
                                }
                            }

                            // Close Button
                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: closeArea.containsMouse ? Theme.errorHover : "transparent"
                                anchors.verticalCenter: parent.verticalCenter

                                DankIcon {
                                    anchors.centerIn: parent
                                    name: "close"
                                    size: Theme.iconSize - 4
                                    color: closeArea.containsMouse ? Theme.error : Theme.surfaceText
                                }

                                MouseArea {
                                    id: closeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: { if (root.popoutService) root.popoutService.close() }
                                }
                            }
                        }

                        // Power Draw & Health Info Cards (Under Nested Surface BG)
                        Row {
                            width: parent.width
                            spacing: Theme.spacingM
                            visible: hasBattery && batteryCapacityPct > 0

                            StyledRect {
                                width: (parent.width - Theme.spacingM) / 2
                                height: 64
                                radius: Theme.cornerRadius
                                color: Theme.nestedSurface
                                border.width: 0

                                Column {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: "Power"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.primary
                                        font.weight: Font.Medium
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                   StyledText {
                                        text: {
                                            const num = parseFloat(batteryWattage)
                                            if (isNaN(num)) return "N/A"
                                            return `${num.toFixed(1)} W`
                                        }
                                        font.pixelSize: Theme.fontSizeLarge
                                        color: Theme.surfaceText
                                        font.weight: Font.Bold
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }

                            StyledRect {
                                width: (parent.width - Theme.spacingM) / 2
                                height: 64
                                radius: Theme.cornerRadius
                                color: Theme.nestedSurface
                                border.width: 0

                                Column {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: "Health"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.primary
                                        font.weight: Font.Medium
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    StyledText {
                                        text: root.batteryHealthPct > 0 ? `${root.batteryHealthPct}%` : "N/A"
                                        font.pixelSize: Theme.fontSizeLarge
                                        color: root.batteryHealthPct > 0 && root.batteryHealthPct < 80 ? Theme.error : Theme.surfaceText
                                        font.weight: Font.Bold
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }
                        }
                    }

                    // ==========================================
                    // 2. GPU SECTION (D-State Split)
                    // ==========================================
                    Column {
                        width: parent.width
                        spacing: Theme.spacingS

                        // GPU Title (Matches Battery)
                        StyledText {
                            text: "GPU"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceTextMedium
                            leftPadding: Theme.spacingS
                        }

                        // Flat Header Row (No Surface BG)
                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            DankIcon {
                                name: "developer_board"
                                size: Theme.iconSizeLarge
                                color: root.dgpuColor
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: parent.width - Theme.iconSizeLarge - Theme.spacingM
                                spacing: 2
                                anchors.verticalCenter: parent.verticalCenter

                                Row {
                                    spacing: Theme.spacingS

                                    StyledText {
                                        text: dgpuState !== "..." ? dgpuState : "N/A"
                                        font.pixelSize: Theme.fontSizeXLarge
                                        font.weight: Font.Bold
                                        color: (dgpuState === "D3cold" || dgpuState === "D3") ? Theme.primary : root.dgpuColor
                                    }

                                    StyledText {
                                        text: (dgpuState === "D3cold" || dgpuState === "D3") ? "Idle" : "Active"
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: Font.Medium
                                        color: root.dgpuColor
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    text: {
                                        if (dgpuState === "D3cold" || dgpuState === "D3" || dgpuState === "D3Hot")
                                            return "GPU is suspended (ideal for saving battery)."
                                        else if (dgpuState === "D0" || dgpuState === "D3ci")
                                            return "GPU is active and drawing power."
                                        else
                                            return `PCI Bus Location: 0000:${root.pciAddr}`
                                    }
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: root.mutedText
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        // Side-by-side Info Cards (Under Nested Surface BG)
                        Row {
                            width: parent.width
                            spacing: Theme.spacingM

                            StyledRect {
                                width: (parent.width - Theme.spacingM) / 2
                                height: 64
                                radius: Theme.cornerRadius
                                color: Theme.nestedSurface
                                border.width: 0

                                Column {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: "Runtime Status"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.primary
                                        font.weight: Font.Medium
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    StyledText {
                                        text: gpuRuntimeStatus !== "..." ? gpuRuntimeStatus : "N/A"
                                        font.pixelSize: Theme.fontSizeLarge
                                        font.weight: Font.Bold
                                        // Automatically inherits the state warning color if active
                                        color: {
                                            if (gpuRuntimeStatus === "...") return Theme.surfaceText
                                            return gpuRuntimeStatus === "active" || gpuRuntimeStatus === "D0" ? root.dgpuColor : Theme.surfaceText
                                        }
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }

                            StyledRect {
                                width: (parent.width - Theme.spacingM) / 2
                                height: 64
                                radius: Theme.cornerRadius
                                color: Theme.nestedSurface
                                border.width: 0

                                Column {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    StyledText {
                                        text: "Power Control"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.primary
                                        font.weight: Font.Medium
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }

                                    StyledText {
                                        text: gpuPowerControl !== "..." ? gpuPowerControl : "N/A"
                                        font.pixelSize: Theme.fontSizeLarge
                                        font.weight: Font.Bold
                                        // "auto" is shown neutrally; non-optimal settings display in warning orange
                                        color: gpuPowerControl === "auto" ? Theme.surfaceText : root.modeHybrid
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }
                            }
                        }
                    }

                    // ==========================================
                    // 3. GPU MODE OPTIONS (FLAT SWITCHERS)
                    // ==========================================

                    // --- supergfxctl Section ---
                    Column {
                        visible: popup.sgfxVisible && root.supergfxctlAvailable
                        width: parent.width
                        spacing: Theme.spacingS

                        StyledText {
                            text: "supergfxctl"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceTextMedium
                            leftPadding: Theme.spacingS
                        }

                        Item {
                            id: sgfxButtonsWrapper
                            width: parent.width
                            height: sgfxButtons.height * sgfxButtons.scale

                            DankButtonGroup {
                                id: sgfxButtons
                                property var modeModel: root.supportedSupergfxctlModes.length > 0 ? root.supportedSupergfxctlModes : ["Integrated", "Hybrid", "Performance"]
                                property int currentModeIndex: modeModel.indexOf(popup.sgfxMode)

                                scale: Math.min(1, parent.width / implicitWidth)
                                transformOrigin: Item.Center
                                anchors.horizontalCenter: parent.horizontalCenter
                                model: modeModel
                                currentIndex: currentModeIndex
                                selectionMode: "single"
                                buttonHeight: 42
                                minButtonWidth: 80
                                textSize: Theme.fontSizeMedium

                                onSelectionChanged: (index, selected) => {
                                    if (!selected) return
                                    root.setSupergfxctlMode(modeModel[index])
                                }
                            }
                        }
                    }

                    // --- cardwire Section ---
                    Column {
                        visible: popup.cwVisible && root.cardwireAvailable
                        width: parent.width
                        spacing: Theme.spacingS

                        StyledText {
                            text: "cardwire"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceTextMedium
                            leftPadding: Theme.spacingS
                        }

                        Item {
                            id: cwButtonsWrapper
                            width: parent.width
                            height: cwButtons.height * cwButtons.scale

                            DankButtonGroup {
                                id: cwButtons
                                property var modeModel: root.supportedCardwireModes.length > 0 ? root.supportedCardwireModes : ["integrated", "hybrid"]
                                property int currentModeIndex: modeModel.indexOf(popup.cwMode)

                                scale: Math.min(1, parent.width / implicitWidth)
                                transformOrigin: Item.Center
                                anchors.horizontalCenter: parent.horizontalCenter
                                model: modeModel
                                currentIndex: currentModeIndex
                                selectionMode: "single"
                                buttonHeight: 42
                                minButtonWidth: 80
                                textSize: Theme.fontSizeMedium

                                onSelectionChanged: (index, selected) => {
                                    if (!selected) return
                                    root.setCardwireMode(modeModel[index])
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}