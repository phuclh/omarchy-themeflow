import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.phuclh.themeflow"

  readonly property var themeflowService: bar?.shell?.serviceFor(root.moduleName)
  property bool popupOpen: false
  property bool popoutSwitchClosing: false

  function close() {
    popupOpen = false
  }

  function open() {
    popupOpen = true
  }

  function toggle() {
    popupOpen = !popupOpen
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    popoutSwitchReset.restart()
  }

  function commitTimes() {
    if (!root.themeflowService) return
    var dayAccepted = root.themeflowService.setDayTime(dayTimeField.text)
    var nightAccepted = root.themeflowService.setNightTime(nightTimeField.text)
    if (!dayAccepted) dayTimeField.text = root.themeflowService.dayTime
    if (!nightAccepted) nightTimeField.text = root.themeflowService.nightTime
  }

  function commitLocation() {
    if (!root.themeflowService) return
    var accepted = root.themeflowService.setLocation(latitudeField.text, longitudeField.text)
    if (!accepted) {
      latitudeField.text = String(root.themeflowService.latitude)
      longitudeField.text = String(root.themeflowService.longitude)
    }
  }

  readonly property bool opened: popupOpen
  readonly property string periodIcon: themeflowService && themeflowService.activePeriod === "day"
    ? "󰖙" : "󰖔"
  readonly property color mutedForeground: bar
    ? Qt.rgba(bar.foreground.r, bar.foreground.g, bar.foreground.b, 0.62)
    : Color.foreground

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Timer {
    id: popoutSwitchReset
    interval: 1
    onTriggered: root.popoutSwitchClosing = false
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.periodIcon
    slotSize: Style.bar.statusSlot
    tooltipText: root.themeflowService
      ? root.themeflowService.statusLabel
        + " · Left-click settings · Right-click "
        + (root.themeflowService.enabled ? "pause" : "enable")
      : "Themeflow is loading"

    onPressed: function(b) {
      if (!root.themeflowService) return
      if (b === Qt.RightButton)
        root.themeflowService.setEnabled(!root.themeflowService.enabled)
      else if (b === Qt.MiddleButton)
        root.themeflowService.maybeRotateWallpaper(true)
      else
        root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(410))
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: dayThemeDropdown.popupOpen
        || nightThemeDropdown.popupOpen
        || scheduleDropdown.popupOpen
        || wallpaperIntervalDropdown.popupOpen
        || dayTimeField.activeFocus
        || nightTimeField.activeFocus
        || latitudeField.activeFocus
        || longitudeField.activeFocus
      onCloseRequested: root.close()

      Flickable {
        id: settingsScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: settingsScroll.width
          spacing: Style.space(12)

      Row {
        width: parent.width
        spacing: Style.space(10)

        Text {
          text: root.periodIcon
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.iconLarge
          anchors.verticalCenter: parent.verticalCenter
        }

        Column {
          width: parent.width - Style.space(48)
          spacing: Style.space(2)

          Text {
            text: "Themeflow"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            text: root.themeflowService
              ? root.themeflowService.statusLabel
              : "Service unavailable"
            color: root.mutedForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            elide: Text.ElideRight
          }
        }
      }

      PanelSeparator { foreground: root.bar.foreground }

      Toggle {
        width: parent.width
        label: "Automatic theme switching"
        description: root.themeflowService && root.themeflowService.enabled
          ? "Next change " + root.themeflowService.nextTransitionLabel
          : "Keep the current theme until automation is enabled."
        foreground: root.bar.foreground
        accent: Color.accent
        fontFamily: root.bar.fontFamily
        checked: root.themeflowService ? root.themeflowService.enabled : false
        onClicked: if (root.themeflowService)
          root.themeflowService.setEnabled(!root.themeflowService.enabled)
      }

      Column {
        width: parent.width
        spacing: Style.space(7)

        Text {
          text: "THEMES"
          color: root.mutedForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Row {
          width: parent.width
          spacing: Style.space(8)

          SearchableDropdown {
            id: dayThemeDropdown
            width: (parent.width - parent.spacing) / 2
            label: "Day"
            fontFamily: root.bar.fontFamily
            placeholderText: "Search light themes…"
            options: root.themeflowService ? root.themeflowService.themeOptions : []
            value: root.themeflowService ? root.themeflowService.dayTheme : ""
            onChanged: function(value) {
              if (root.themeflowService) root.themeflowService.setDayTheme(value)
            }
          }

          SearchableDropdown {
            id: nightThemeDropdown
            width: (parent.width - parent.spacing) / 2
            label: "Night"
            fontFamily: root.bar.fontFamily
            placeholderText: "Search dark themes…"
            options: root.themeflowService ? root.themeflowService.themeOptions : []
            value: root.themeflowService ? root.themeflowService.nightTheme : ""
            onChanged: function(value) {
              if (root.themeflowService) root.themeflowService.setNightTheme(value)
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(7)

        Text {
          text: "SCHEDULE"
          color: root.mutedForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Dropdown {
          id: scheduleDropdown
          width: parent.width
          label: "Switch by"
          fontFamily: root.bar.fontFamily
          options: [
            { value: "fixed", label: "Fixed times" },
            { value: "solar", label: "Sunrise & sunset" }
          ]
          value: root.themeflowService ? root.themeflowService.scheduleMode : "fixed"
          onChanged: function(value) {
            if (root.themeflowService) root.themeflowService.setScheduleMode(value)
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          visible: !root.themeflowService || root.themeflowService.scheduleMode === "fixed"

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.space(3)

            Text {
              text: "Day begins"
              color: root.mutedForeground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            TextField {
              id: dayTimeField
              width: parent.width
              text: root.themeflowService ? root.themeflowService.dayTime : "07:00"
              placeholderText: "07:00"
              foreground: root.bar.foreground
              accent: Color.accent
              font.family: root.bar.fontFamily
              onEditingFinished: root.commitTimes()
            }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.space(3)

            Text {
              text: "Night begins"
              color: root.mutedForeground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            TextField {
              id: nightTimeField
              width: parent.width
              text: root.themeflowService ? root.themeflowService.nightTime : "19:00"
              placeholderText: "19:00"
              foreground: root.bar.foreground
              accent: Color.accent
              font.family: root.bar.fontFamily
              onEditingFinished: root.commitTimes()
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.themeflowService && root.themeflowService.scheduleMode === "solar"

          Toggle {
            width: parent.width
            label: "Automatic location"
            description: root.themeflowService
              ? root.themeflowService.solarLocationLabel
              : "Detecting location…"
            foreground: root.bar.foreground
            accent: Color.accent
            fontFamily: root.bar.fontFamily
            checked: root.themeflowService
              ? root.themeflowService.solarLocationMode === "automatic" : true
            onClicked: if (root.themeflowService)
              root.themeflowService.setAutomaticLocation(
                root.themeflowService.solarLocationMode !== "automatic")
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: root.themeflowService
              && root.themeflowService.solarLocationMode === "automatic"

            Text {
              width: parent.width - refreshLocationButton.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              text: "Uses your Omarchy Weather location first, then approximate network location."
              color: root.mutedForeground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Button {
              id: refreshLocationButton
              text: root.themeflowService && root.themeflowService.automaticLocationLoading
                ? "Detecting…" : "Refresh"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              enabled: root.themeflowService
                && !root.themeflowService.automaticLocationLoading
              onClicked: root.themeflowService.requestAutomaticLocation(true)
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: root.themeflowService
              && root.themeflowService.solarLocationMode === "manual"

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              Text {
                text: "Latitude"
                color: root.mutedForeground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              TextField {
                id: latitudeField
                width: parent.width
                text: root.themeflowService ? String(root.themeflowService.latitude) : "0"
                placeholderText: "37.7749"
                foreground: root.bar.foreground
                accent: Color.accent
                font.family: root.bar.fontFamily
                onEditingFinished: root.commitLocation()
              }
            }

            Column {
              width: (parent.width - parent.spacing) / 2
              spacing: Style.space(3)

              Text {
                text: "Longitude"
                color: root.mutedForeground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              TextField {
                id: longitudeField
                width: parent.width
                text: root.themeflowService ? String(root.themeflowService.longitude) : "0"
                placeholderText: "−122.4194"
                foreground: root.bar.foreground
                accent: Color.accent
                font.family: root.bar.fontFamily
                onEditingFinished: root.commitLocation()
              }
            }
          }

          Text {
            width: parent.width
            text: root.themeflowService && root.themeflowService.scheduleSource === "fixed-fallback"
              ? "Sun times are unavailable here; fixed times are being used."
              : "Sunrise and sunset are calculated locally for the detected location."
            color: root.themeflowService && root.themeflowService.scheduleSource === "fixed-fallback"
              ? Color.accent : root.mutedForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(7)

        Text {
          text: "WALLPAPERS"
          color: root.mutedForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Toggle {
          width: parent.width
          label: "Rotate theme wallpapers"
          description: "Cycle through all backgrounds provided by the active theme."
          foreground: root.bar.foreground
          accent: Color.accent
          fontFamily: root.bar.fontFamily
          checked: root.themeflowService
            ? root.themeflowService.wallpaperRotationEnabled : false
          onClicked: if (root.themeflowService)
            root.themeflowService.setWallpaperRotationEnabled(
              !root.themeflowService.wallpaperRotationEnabled)
        }

        Dropdown {
          id: wallpaperIntervalDropdown
          width: parent.width
          label: "Change every"
          fontFamily: root.bar.fontFamily
          enabled: root.themeflowService
            ? root.themeflowService.wallpaperRotationEnabled : false
          options: [
            { value: 5, label: "5 minutes" },
            { value: 15, label: "15 minutes" },
            { value: 30, label: "30 minutes" },
            { value: 60, label: "1 hour" },
            { value: 120, label: "2 hours" },
            { value: 240, label: "4 hours" },
            { value: 480, label: "8 hours" },
            { value: 1440, label: "1 day" }
          ]
          value: root.themeflowService
            ? root.themeflowService.wallpaperIntervalMinutes : 60
          onChanged: function(value) {
            if (root.themeflowService) root.themeflowService.setWallpaperInterval(value)
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Button {
          width: (parent.width - parent.spacing) / 2
          text: "Apply now"
          iconText: "󰑐"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          bordered: true
          enabled: root.themeflowService && !root.themeflowService.busy
          onClicked: root.themeflowService.evaluateSchedule(true)
        }

        Button {
          width: (parent.width - parent.spacing) / 2
          text: "Next wallpaper"
          iconText: "󰆊"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          bordered: true
          enabled: root.themeflowService && !root.themeflowService.busy
          onClicked: root.themeflowService.maybeRotateWallpaper(true)
        }
      }

        Text {
          width: parent.width
          visible: root.themeflowService
            && (root.themeflowService.lastError !== ""
              || root.themeflowService.lastAction !== "")
          text: root.themeflowService && root.themeflowService.lastError !== ""
            ? root.themeflowService.lastError
            : (root.themeflowService ? root.themeflowService.lastAction : "")
          color: root.themeflowService && root.themeflowService.lastError !== ""
            ? Color.accent : root.mutedForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }
        }
      }
    }
  }
}
