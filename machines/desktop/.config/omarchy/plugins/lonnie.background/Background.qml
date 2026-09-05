import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"
  readonly property string overrideDir: stateHome + "/omarchy/backgrounds-by-monitor"
  readonly property string pluginDir: home + "/.config/omarchy/plugins/lonnie.background"

  // screen name -> absolute image path. A screen absent from this map follows
  // the global background, so themes keep working on every screen that has not
  // been deliberately overridden.
  property var overrides: ({})

  function overrideFor(screenName) {
    var path = overrides[screenName]
    return path ? path : ""
  }

  property string currentBackground: ""
  property string displayedBackground: ""
  property string incomingBackground: ""
  property string oldBackground: ""
  property bool finishingTransition: false
  property int backgroundVersion: 0
  property int revealStartedVersion: -1
  property int pendingThemeVersion: -1
  property string pendingColorsRaw: ""
  property string pendingShellRaw: ""
  property real revealProgress: 1

  function imageUrl(path) {
    return Util.fileUrl(path)
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
    if (!readOverridesProc.running) readOverridesProc.running = true
  }

  function setBackground(path, instant) {
    transitionBackground("", path, path, instant, false)
  }

  function transitionBackground(fromPath, path, finalPath, instant, force) {
    path = String(path || "").trim()
    finalPath = String(finalPath || path).trim()
    fromPath = String(fromPath || "").trim()
    if (!path || (!force && finalPath === currentBackground)) return
    currentBackground = finalPath
    backgroundVersion += 1
    revealStartedVersion = -1

    revealAnimation.stop()
    finishingTransition = false

    if (instant || !displayedBackground) {
      oldBackground = ""
      incomingBackground = ""
      displayedBackground = path
      revealProgress = 1
      return
    }

    oldBackground = fromPath || displayedBackground
    incomingBackground = path
    revealProgress = 0
  }

  function setPendingTheme(colorsB64, shellB64) {
    pendingColorsRaw = Util.decodeBase64(colorsB64)
    pendingShellRaw = Util.decodeBase64(shellB64)
    pendingThemeVersion = backgroundVersion
    pendingThemeFallbackTimer.restart()
  }

  function applyPendingTheme() {
    // Background polling can advance backgroundVersion while a theme switch is
    // pending; the latest theme payload should still apply.
    if (pendingThemeVersion < 0) return
    pendingThemeFallbackTimer.stop()
    Color.loadColors(pendingColorsRaw)
    // Color.loadShell also refreshes Style so the type scale flips with the
    // background reveal instead of waiting for a separate reload path.
    Color.loadShell(pendingShellRaw)
    Style.scheduleRefresh()
    pendingThemeVersion = -1
    pendingColorsRaw = ""
    pendingShellRaw = ""
  }

  function transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64) {
    transitionBackground(fromPath, path, finalPath, false, true)
    setPendingTheme(colorsB64, shellB64)
    if (!incomingBackground || revealProgress >= 1) applyPendingTheme()
  }

  function startReveal(panel) {
    if (!incomingBackground) return
    panel.maskReady = true
    if (revealStartedVersion === backgroundVersion) return
    revealStartedVersion = backgroundVersion
    applyPendingTheme()
    revealAnimation.restart()
  }

  // Stock opened a selector that set the ONE global background. Now the screen
  // that was double-clicked is what gets changed.
  property double selectorStartedAt: 0

  function openSelectorFor(screenName) {
    var name = String(screenName || "")
    if (!name) {
      console.log("background: double-click with no screen name; ignoring")
      return
    }

    if (bgSwitchProc.running) {
      // A selector really can still be open, and swallowing the click is right
      // then. But without an escape hatch a process that never reports exit
      // leaves double-click dead forever with no visible cause, so give up on
      // it after a while rather than silently ignoring every click.
      var age = Date.now() - selectorStartedAt
      if (age < 120000) {
        console.log("background: selector already open (" + Math.round(age / 1000) + "s); ignoring click on " + name)
        return
      }
      console.log("background: selector stuck for " + Math.round(age / 1000) + "s; restarting for " + name)
      bgSwitchProc.running = false
    }

    // Assign the command imperatively instead of binding it to a property.
    // As a binding it could still hold the previous (or empty) screen name at
    // the moment `running` flips, launching the helper with a stale argument --
    // and an empty one makes it exit with a usage error to a discarded stderr,
    // which looks exactly like the double-click doing nothing.
    bgSwitchProc.command = ["bash", root.pluginDir + "/set-monitor-background", name]
    selectorStartedAt = Date.now()
    bgSwitchProc.running = true
  }

  function openThemeSwitcher() {
    if (!themeSwitchProc.running) themeSwitchProc.running = true
  }

  Process {
    id: bgSwitchProc
    // command is assigned in openSelectorFor(), not bound -- see the note there.
    stderr: StdioCollector {
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err) console.log("background: selector stderr: " + err)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) console.log("background: selector exited " + exitCode)
      root.refreshBackground()
    }
  }

  // One line per override: "<screen>\t<absolute path>".
  Process {
    id: readOverridesProc
    command: ["bash", "-c",
      "d=\"$HOME/.local/state/omarchy/backgrounds-by-monitor\"; " +
      "[ -d \"$d\" ] || exit 0; " +
      "for f in \"$d\"/*; do " +
      "  [ -e \"$f\" ] || continue; " +
      "  printf '%s\\t%s\\n' \"$(basename \"$f\")\" \"$(readlink -f \"$f\")\"; " +
      "done"]
    stdout: StdioCollector {
      onStreamFinished: {
        var map = {}
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].trim()
          if (!line) continue
          var parts = line.split("\t")
          // A theme switch replaces current/theme/backgrounds, so an override
          // pointing in there can vanish. readlink -f yields an empty second
          // field then, and the screen quietly falls back to the global image.
          if (parts.length === 2 && parts[1]) map[parts[0]] = parts[1]
        }
        root.overrides = map
      }
    }
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
    onExited: root.refreshBackground()
  }

  Process {
    id: readlinkProc
    command: ["readlink", "-f", root.currentBackgroundLink]
    stdout: StdioCollector {
      onStreamFinished: root.setBackground(String(text || "").trim(), false)
    }
  }

  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshBackground()
    }

    function set(path: string): void {
      root.setBackground(path, false)
    }

    function setInstant(path: string): void {
      root.setBackground(path, true)
    }

    function transition(fromPath: string, path: string): void {
      root.transitionBackground(fromPath, path, path, false, false)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string, colorsB64: string, shellB64: string): void {
      root.transitionBackgroundWithTheme(fromPath, path, finalPath, colorsB64, shellB64)
    }
  }

  Timer {
    id: pendingThemeFallbackTimer
    interval: 300
    repeat: false
    onTriggered: root.applyPendingTheme()
  }

  NumberAnimation {
    id: revealAnimation
    target: root
    property: "revealProgress"
    from: 0
    to: 1
    duration: 420
    easing.type: Easing.InOutCubic
    onFinished: {
      if (root.incomingBackground) {
        root.displayedBackground = root.currentBackground || root.incomingBackground
        root.finishingTransition = true
      }
      root.revealProgress = 1
    }
  }

  Component.onCompleted: refreshBackground()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: !remapGuard.remapping
      anchors { top: true; bottom: true; left: true; right: true }

      ScreenMoveRemap {
        id: remapGuard
        window: panel
      }
      color: "transparent"
      // Keep render updates enabled. The background layer has been observed to
      // lose its committed buffer while parked with updatesEnabled=false,
      // leaving a black desktop until omarchy-shell is restarted. The wallpaper
      // itself is static, so this favors correctness over a small render-loop
      // optimization.
      updatesEnabled: true

      property bool maskReady: false

      // Empty for screens that follow the global background.
      readonly property string overrideBg: root.overrideFor(modelData.name)
      readonly property bool hasOverride: overrideBg !== ""

      function maybeStartReveal() {
        if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
        if (incomingFrame.status !== Image.Ready) return
        Qt.callLater(function() {
          if (!root.incomingBackground || root.revealProgress !== 0 || maskReady) return
          if (incomingFrame.status !== Image.Ready) return
          root.startReveal(panel)
        })
      }

      WlrLayershell.namespace: "omarchy-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      Image {
        id: base
        anchors.fill: parent
        source: root.imageUrl(root.displayedBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        onStatusChanged: {
          if (status === Image.Ready && root.finishingTransition) {
            root.incomingBackground = ""
            root.oldBackground = ""
            root.finishingTransition = false
          }
        }
      }

      Image {
        id: oldFrame
        anchors.fill: parent
        source: root.imageUrl(root.oldBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true
        visible: root.oldBackground !== "" && root.revealProgress < 1
        onStatusChanged: panel.maybeStartReveal()
      }

      Item {
        id: incomingLayer
        anchors.fill: parent
        visible: root.incomingBackground !== "" && incomingFrame.status === Image.Ready && (root.revealProgress >= 1 || panel.maskReady)
        layer.enabled: root.incomingBackground !== "" && root.revealProgress < 1
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: revealMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 0.02
        }

        Image {
          id: incomingFrame
          anchors.fill: parent
          source: root.imageUrl(root.incomingBackground)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          mipmap: true
          onStatusChanged: panel.maybeStartReveal()
        }
      }

      Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        readonly property real slant: -0.18
        readonly property real centerTop: width / 2 - slant * height / 2
        readonly property real centerBottom: width / 2 + slant * height / 2
        readonly property real reach: width / 2 + Math.abs(slant) * height / 2 + 4
        readonly property real spread: reach * root.revealProgress

        Shape {
          anchors.fill: parent
          antialiasing: true
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: "white"
            strokeColor: "transparent"
            startX: revealMask.centerTop - revealMask.spread; startY: 0
            PathLine { x: revealMask.centerTop + revealMask.spread; y: 0 }
            PathLine { x: revealMask.centerBottom + revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerBottom - revealMask.spread; y: revealMask.height }
            PathLine { x: revealMask.centerTop - revealMask.spread; y: 0 }
          }
        }
      }

      Connections {
        target: root
        function onIncomingBackgroundChanged() {
          panel.maskReady = false
          panel.maybeStartReveal()
        }
      }

      // Drawn opaque over the global transition stack. The reveal animation is
      // driven by single root-level properties, so rather than rework it per
      // screen an overridden monitor simply covers it -- the global background
      // still transitions correctly on the screens that use it.
      Image {
        id: overrideFrame
        anchors.fill: parent
        source: root.imageUrl(panel.overrideBg)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        mipmap: true
        visible: panel.hasOverride && status === Image.Ready
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) root.openThemeSwitcher()
          else root.openSelectorFor(panel.modelData.name)
          mouse.accepted = true
        }
      }
    }
  }
}
