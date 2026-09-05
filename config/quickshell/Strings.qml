pragma Singleton

//  UI text for every panel, in one place.
//
//  Why: every panel had its labels hardcoded to German -- fine for the one
//  person who wrote it, but for an English-speaking audience the panels
//  themselves are the screenshots, and a screenshot cannot be cropped around
//  a label. Rather than rewrite every literal in place, they now resolve
//  through this map, and the German original stays one
//  `~/.config/hypr/lang` away.
//
//  Read once, synchronously, like Theme reads its colour scheme: the file is
//  tiny and this only needs to be right before the first frame, not kept live.
//  Missing file (the common case -- nobody but this machine has it) means
//  English, which is also the right default for a stranger's first run.

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: strings

    FileView {
        id: langFile
        path: "/home/woofi/.config/hypr/lang"
        blockLoading: true
        printErrors: false
    }

    readonly property string lang: langFile.text().trim() === "de" ? "de" : "en"
    readonly property string locale: lang === "de" ? "de_DE" : "en_US"

    readonly property var en: ({
        desktops: "DESKTOPS",
        workspaceEmpty: "empty",
        dnd: "Do Not Disturb",
        clearAll: "Clear all",
        clearHistory: "Clear history",
        noEvents: "No events",
        noWindows: "No windows",
        noNotifications: "No notifications",
        noDevicesFound: "No devices found",
        searchingDevices: "Searching for devices…",
        scanning: "Scanning…",
        searchDevices: "Search for devices",
        available: "AVAILABLE",
        powerMode: "POWER MODE",
        appearance: "APPEARANCE",
        brightness: "BRIGHTNESS",
        volume: "VOLUME",
        system: "SYSTEM",
        bluetooth: "BLUETOOTH",
        nightLight: "NIGHT LIGHT",
        playback: "PLAYBACK",
        clipboardHeader: "CLIPBOARD",
        applications: "APPLICATIONS",
        places: "PLACES",
        wifi: "WI-FI",
        battery: "Battery",
        uptime: "Uptime",
        processor: "Processor",
        memory: "Memory",
        temperature: "Temperature",
        notifications: "Notifications",
        settings: "Settings",
        poweredOn: "On",
        poweredOff: "Off",
        scheduleActive: "Schedule active",
        warmer: "Warmer",
        nothingPlaying: "Nothing playing",
        advancedNetworkSettings: "Advanced network settings",
        addSwitchPoint: "+ Switch point",
        applyToAllDays: "to all days",
        loading: "loading …",
        search: "Search…",
        searchNetworks: "Searching for networks…",
        muted: "muted",
        allDay: "all day",
        scheduleNote: "Changes apply immediately. SUPER+SHIFT+N switches manually; "
                    + "the schedule takes over again at the next switch point.",
        weekdays: ["Mo","Tu","We","Th","Fr","Sa","Su"],
        presetDaylight: "Daylight",
        presetNeutral: "Neutral",
        presetWarm: "Warm",
        presetVeryWarm: "Very warm",
        powerPerformance: "Performance",
        powerBalanced: "Balanced",
        powerSaver: "Power saver",
        appearanceDark: "Dark",
        appearanceLight: "Light",
        actionLock: "Lock",
        actionLogout: "Log out",
        actionSuspend: "Suspend",
        actionRestart: "Restart",
        actionShutdown: "Shut down",
        battCharging: "Charging",
        battFull: "Full",
        battOnBattery: "On battery",
        appFiles: "Files",
        imageLabel: "Image",
        historyEmpty: "History is empty",
        nothingFound: "Nothing found",
        altTabHint: "Down arrow for all windows",
        passwordForPrefix: "Password for \"",
        passwordForSuffix: "\""
    })

    readonly property var de: ({
        desktops: "ARBEITSFLÄCHEN",
        workspaceEmpty: "leer",
        dnd: "Nicht stören",
        clearAll: "Alle löschen",
        clearHistory: "Verlauf löschen",
        noEvents: "Keine Termine",
        noWindows: "Keine Fenster",
        noNotifications: "Keine Benachrichtigungen",
        noDevicesFound: "Keine Geräte gefunden",
        searchingDevices: "Suche Geräte…",
        scanning: "Suche läuft…",
        searchDevices: "Nach Geräten suchen",
        available: "VERFÜGBAR",
        powerMode: "ENERGIEMODUS",
        appearance: "ERSCHEINUNGSBILD",
        brightness: "HELLIGKEIT",
        volume: "LAUTSTÄRKE",
        system: "SYSTEM",
        bluetooth: "BLUETOOTH",
        nightLight: "NACHTLICHT",
        playback: "WIEDERGABE",
        clipboardHeader: "ZWISCHENABLAGE",
        applications: "ANWENDUNGEN",
        places: "ORTE",
        wifi: "WLAN",
        battery: "Akku",
        uptime: "Laufzeit",
        processor: "Prozessor",
        memory: "Arbeitsspeicher",
        temperature: "Temperatur",
        notifications: "Benachrichtigungen",
        settings: "Einstellungen",
        poweredOn: "Eingeschaltet",
        poweredOff: "Ausgeschaltet",
        scheduleActive: "Zeitplan aktiv",
        warmer: "Wärmer",
        nothingPlaying: "Nichts wird abgespielt",
        advancedNetworkSettings: "Erweiterte Netzwerkeinstellungen",
        addSwitchPoint: "+ Umschaltpunkt",
        applyToAllDays: "auf alle Tage",
        loading: "wird geladen …",
        search: "Suchen…",
        searchNetworks: "Suche Netzwerke…",
        muted: "stumm",
        allDay: "ganztg",
        scheduleNote: "Änderungen wirken sofort. SUPER+SHIFT+N schaltet manuell um; "
                    + "der Zeitplan übernimmt beim nächsten Umschaltpunkt wieder.",
        weekdays: ["Mo","Di","Mi","Do","Fr","Sa","So"],
        presetDaylight: "Tageslicht",
        presetNeutral: "Neutral",
        presetWarm: "Warm",
        presetVeryWarm: "Sehr warm",
        powerPerformance: "Leistung",
        powerBalanced: "Ausgeglichen",
        powerSaver: "Energiesparen",
        appearanceDark: "Dunkel",
        appearanceLight: "Hell",
        actionLock: "Sperren",
        actionLogout: "Abmelden",
        actionSuspend: "Bereitschaft",
        actionRestart: "Neu starten",
        actionShutdown: "Herunterfahren",
        battCharging: "Wird geladen",
        battFull: "Voll",
        battOnBattery: "Akkubetrieb",
        appFiles: "Dateien",
        imageLabel: "Bild",
        historyEmpty: "Verlauf ist leer",
        nothingFound: "Nichts gefunden",
        altTabHint: "Pfeil runter für alle Fenster",
        passwordForPrefix: "Passwort für „",
        passwordForSuffix: "“"
    })

    readonly property var t: lang === "de" ? de : en

    function passwordFor(name) { return t.passwordForPrefix + name + t.passwordForSuffix; }
}
