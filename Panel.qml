import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

/*
 * Oshelly: run one of your shell commands from the bar.
 *
 * The panel does not read the config. It asks oshelly for the list with
 * `list --json`, and clicking a name asks oshelly to launch it with `run`.
 * That keeps one parser and one idea of what a name means, and it means this
 * file has no opinion about terminals or about the config syntax.
 *
 * The CLI starts the terminal and returns. It does not run the command
 * itself, and this panel does not either, so an interactive script is just
 * another line in the config.
 */
Panel {
    id: root

    moduleName: "h1st0ry3d.oshelly"
    ipcTarget: "h1st0ry3d.oshelly"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // -- the program this panel needs
    /*
     * Where oshelly is looked for, in order. The first is the conventional
     * place for something installed system-wide; the second needs no
     * privileges, which is why it is here too.
     */
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property var cliCandidates: [
        "/usr/local/bin/oshelly",
        root.homeDir + "/.local/bin/oshelly"
    ]

    // Resolved once at startup. Empty until the probe finishes, so nothing is
    // sent at a path that has not been checked.
    property string cliPath: ""
    property bool cliMissing: false

    /*
     * The CLI launches a terminal, and a terminal needs the session it is in:
     * WAYLAND_DISPLAY, DISPLAY, XDG_RUNTIME_DIR, DBUS_SESSION_BUS_ADDRESS and
     * the rest. Unlike the odisplay panel, this Process therefore inherits
     * the shell's environment instead of clearing it. The command that runs in
     * the terminal is the user's own code and already has the user's access;
     * withholding the environment would only stop the terminal from opening.
     */

    /*
     * Find oshelly, and say so plainly if it is not there. A panel whose
     * buttons silently do nothing is the outcome to avoid, so this is checked at
     * startup rather than discovered on the first click.
     */
    Process {
        id: cliProbe
        running: false
        property int attempt: 0
        stdout: SplitParser { onRead: function(chunk) {} }
        stderr: SplitParser { onRead: function(chunk) {} }
        command: ["/usr/bin/test", "-x", root.cliCandidates[cliProbe.attempt]]

        onExited: function(code) {
            if (code === 0) {
                root.cliPath = root.cliCandidates[cliProbe.attempt]
                root.cliMissing = false
                // A previous probe may have left "not installed" on screen.
                // Clear it now rather than leaving it there until the list
                // below finishes reading.
                root.statusIsError = false
                root.statusText = "Run a command"
                root.statusDetail = ""
                // The panel may have been opened while this probe was still
                // running, and refresh does nothing without a path. Read now
                // as well, so which of the two happened first does not decide
                // whether the panel has any rows.
                root.refresh()
                return
            }
            cliProbe.attempt++
            if (cliProbe.attempt < root.cliCandidates.length) {
                cliProbe.command = ["/usr/bin/test", "-x", root.cliCandidates[cliProbe.attempt]]
                cliProbe.running = true
                return
            }
            root.cliMissing = true
            root.statusIsError = true
            root.statusText = "oshelly is not installed."
            root.statusDetail = "Put the oshelly binary at " + root.cliCandidates[0]
                + " or " + root.cliCandidates[1] + ", then reopen the panel."
        }
    }

    // A probe is not repeated on its own. Opening the panel tries again, which
    // is what makes "build the CLI and reopen the panel" work without
    // restarting the shell. A successful probe leaves cliMissing false, so
    // later opens read the config instead of testing for the binary again.
    function probe() {
        if (cliProbe.running) return
        cliProbe.attempt = 0
        cliProbe.command = ["/usr/bin/test", "-x", root.cliCandidates[0]]
        cliProbe.running = true
    }

    // -- the list, read back from oshelly
    /*
     * The commands exactly as the CLI parsed them. The panel does not keep a
     * second copy of the file, because then a line with a typo in it could be
     * drawn one way here and refused another way there.
     */
    property var loaded: null
    property bool loadedReady: false
    property bool configError: false
    readonly property var commands: root.loadedReady && root.loaded && root.loaded.commands
        ? root.loaded.commands : []

    readonly property string configPath: root.loaded && root.loaded.path
        ? root.loaded.path : "~/.config/oshelly/oshelly.conf"

    // -- status
    property bool statusIsError: false
    property string statusText: "Run a command"
    property string statusDetail: ""

    // The row the keyboard is on. A click is the ordinary way to use this, but
    // a bar panel is reachable by keyboard, and a list that cannot be walked
    // with the arrow keys is a list that only works with a mouse.
    property int cursor: 0

    /*
     * An oversized reply is cut off rather than collected whole. The CLI
     * prints a list of names, so this is a backstop, not a budget to fill.
     */
    readonly property int outputLimit: 65536

    /*
     * oshelly launches a terminal and exits. This is only a backstop for one
     * that has wedged, and it is generous because a machine under load can be
     * slow to start a terminal.
     */
    readonly property int actionWatchdogMs: 15000
    readonly property int settingsWatchdogMs: 5000

    // The power column on each command row. One glyph, so it is narrower than
    // the command button.
    readonly property int closeColumnWidth: Style.space(32)
    readonly property int columnGap: Style.space(6)

    function refresh() {
        if (root.cliPath === "") return
        if (settingsProcess.running) {
            // A read already in flight finishes rather than being restarted.
            // Starting a second one would throw away the JSON being read.
            root.settingsAgain = true
            return
        }
        settingsProcess.buffer = ""
        settingsProcess.failure = ""
        settingsProcess.command = [root.cliPath, "list", "--json"]
        settingsProcess.running = true
        settingsTimeout.restart()
    }

    property bool settingsAgain: false

    Process {
        id: settingsProcess
        running: false
        property string buffer: ""
        property string failure: ""

        // An empty split marker hands over raw chunks, so an oversized reply
        // can be cut off. A line-buffered parser has to hold the whole line.
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(chunk) {
                if (settingsProcess.buffer.length <= root.outputLimit)
                    settingsProcess.buffer += chunk
            }
        }
        stderr: SplitParser {
            onRead: function(line) { settingsProcess.failure = line }
        }
        command: [root.cliPath, "list", "--json"]

        onExited: function(code) {
            settingsTimeout.stop()
            var text = settingsProcess.buffer
            settingsProcess.buffer = ""

            // Whatever happened, a read that was asked for while this one was
            // running still has to happen.
            if (root.settingsAgain) {
                root.settingsAgain = false
                root.refresh()
                return
            }
            if (code !== 0) {
                root.configError = true
                root.loadedReady = false
                root.statusIsError = true
                root.statusText = "Could not read the oshelly config."
                root.statusDetail = root.sentence(
                    settingsProcess.failure !== "" ? settingsProcess.failure : text)
                return
            }

            var parsed = null
            try { parsed = JSON.parse(String(text).trim() || "null") } catch (e) { parsed = null }
            if (!parsed || !parsed.commands) {
                root.configError = true
                root.loadedReady = false
                root.statusIsError = true
                root.statusText = "Could not read the oshelly settings."
                root.statusDetail = "oshelly printed something this panel does not understand."
                return
            }

            root.loaded = parsed
            root.loadedReady = true
            root.configError = false
            if (!root.cliMissing) {
                root.statusIsError = false
                root.statusDetail = ""
                root.statusText = "Run a command"
            }
            if (root.cursor >= root.commands.length)
                root.cursor = Math.max(0, root.commands.length - 1)
        }
    }

    Timer {
        id: settingsTimeout
        interval: root.settingsWatchdogMs
        repeat: false
        onTriggered: {
            if (!settingsProcess.running) return
            settingsProcess.failure = "oshelly did not answer in time."
            settingsProcess.signal(15)
        }
    }

    // -- one action at a time
    /*
     * `run` and `edit` are both one short call to oshelly that hands work to
     * another program and returns. Sharing the process keeps the panel from
     * needing two copies of the watchdog, the error line and the close-on-
     * success rule.
     */
    property string pendingAction: ""
    property string pendingName: ""
    property string pendingValue: ""
    property bool actionTimedOut: false

    function beginAction(kind, name, status, command) {
        root.pendingAction = kind
        root.pendingName = name
        root.actionTimedOut = false
        root.statusIsError = false
        root.statusDetail = ""
        root.statusText = status
        actionProcess.output = ""
        actionProcess.failure = ""
        actionProcess.command = command
        actionProcess.running = true
        actionTimeout.restart()
    }

    function launch(name) {
        if (root.cliPath === "" || actionProcess.running) return
        root.beginAction("run", String(name), "Launching " + root.plain(name, 60),
            [root.cliPath, "run", String(name)])
    }

    function applyCloseLocally(name, close) {
        if (!root.loaded || !root.loaded.commands) return
        var next = JSON.parse(JSON.stringify(root.loaded))
        for (var index = 0; index < next.commands.length; index++) {
            if (next.commands[index].name === name) next.commands[index].close = close
        }
        root.loaded = next
    }

    /*
     * The power button on a row. It is a setting, not a launch, so it writes
     * through the CLI and leaves the panel open. The local row changes first
     * so the button answers the click; a failed write puts it back.
     */
    function toggleClose(entry) {
        if (root.cliPath === "" || actionProcess.running) return
        var on = entry.close !== true
        root.pendingValue = on ? "on" : "off"
        root.applyCloseLocally(entry.name, on)
        root.beginAction("close", entry.name,
            on ? "Closing the terminal after this command" : "Keeping the terminal open",
            [root.cliPath, "set", "close", entry.name, on ? "on" : "off"])
    }

    /*
     * The header button's action, and the same division of work as `run`: the
     * CLI knows where the config is and how to ask the desktop for its editor,
     * so a panel in the bar and a menu bar app cannot disagree about which file
     * opens or which editor opens it.
     */
    function editConfig() {
        if (root.cliPath === "" || actionProcess.running) return
        root.beginAction("edit", "", "Opening the config...", [root.cliPath, "edit"])
    }

    Process {
        id: actionProcess
        running: false
        property string output: ""
        property string failure: ""

        stdout: SplitParser {
            onRead: function(line) { actionProcess.output = line }
        }
        stderr: SplitParser {
            onRead: function(line) { actionProcess.failure = line }
        }
        command: [root.cliPath, "run", ""]

        onExited: function(code) {
            actionTimeout.stop()
            if (root.actionTimedOut) {
                root.actionTimedOut = false
                root.statusIsError = true
                if (root.pendingAction === "close") {
                    root.applyCloseLocally(root.pendingName, root.pendingValue !== "on")
                    root.statusText = "Could not change Close after run"
                    root.statusDetail = "The setting was not saved. Run `oshelly doctor` in a terminal."
                } else {
                    root.statusText = "oshelly did not answer."
                    root.statusDetail = root.pendingAction === "edit"
                        ? "The config was not opened. Run `oshelly doctor` in a terminal."
                        : "The command was not launched. Run `oshelly doctor` in a terminal."
                }
                return
            }
            if (code === 0) {
                root.statusIsError = false
                if (root.pendingAction === "close") {
                    root.statusText = (root.pendingValue === "on"
                        ? "Close after run: on for "
                        : "Close after run: off for ") + root.plain(root.pendingName, 40)
                    return
                }
                if (root.pendingAction === "edit") {
                    root.statusText = "Editing the config"
                } else {
                    root.statusText = "Launched " + root.plain(root.pendingName, 60)
                }
                // The terminal or the editor is already opening. Leaving the
                // panel on top of it would hide the thing the click was for.
                root.close()
                return
            }
            root.statusIsError = true
            if (root.pendingAction === "close") {
                root.applyCloseLocally(root.pendingName, root.pendingValue !== "on")
                root.statusText = "Could not change Close after run"
            } else if (root.pendingAction === "edit") {
                root.statusText = "Could not open the config"
            } else {
                root.statusText = "Could not run " + root.plain(root.pendingName, 60)
            }
            root.statusDetail = root.sentence(
                actionProcess.failure !== "" ? actionProcess.failure : actionProcess.output)
        }
    }

    Timer {
        id: actionTimeout
        interval: root.actionWatchdogMs
        repeat: false
        onTriggered: {
            if (!actionProcess.running) return
            root.actionTimedOut = true
            actionProcess.signal(15)
        }
    }

    // -- keyboard
    function moveCursor(dy) {
        if (root.commands.length === 0) return
        root.cursor = (root.cursor + dy + root.commands.length) % root.commands.length
    }

    function activateCursor() {
        if (root.commands.length === 0) return
        if (root.cursor < 0 || root.cursor >= root.commands.length) return
        root.launch(root.commands[root.cursor].name)
    }

    // -- untrusted text
    /*
     * Names and the CLI's own error lines come off disk or out of a program,
     * and some of the labels here are rendered by the shell itself, where
     * textFormat cannot be set. Strip what a rich-text renderer could act on
     * and cap the length, for those labels.
     *
     * A line break becomes a space rather than being dropped, so a wrapped
     * label reads as one line rather than two glued-together words.
     */
    function plain(value, limit) {
        var source = String(value === undefined || value === null ? "" : value)
        var cleaned = ""
        for (var index = 0; index < source.length && cleaned.length < limit; index++) {
            var character = source[index]
            var code = source.charCodeAt(index)
            var notSurrogate = !(code >= 0xd800 && code <= 0xdfff)
            var printable = code >= 0x20 && code !== 0x7f && code < 0xa0
            if (notSurrogate && (character === " " || character === "\n" || character === "\r" || character === "\t")) {
                if (cleaned === "" || /\s$/.test(cleaned)) continue
                cleaned += " "
            } else if (printable && notSurrogate && character !== "<" && character !== ">" && character !== "&") {
                cleaned += character
            }
        }
        return cleaned.trim()
    }

    /*
     * The CLI's error lines are already one sentence, and the Text that shows
     * them is Text.PlainText, so this only joins and trims. It deliberately
     * keeps <, > and &: an error may quote a command containing && or a
     * redirect, and dropping those characters would change what it says.
     */
    /*
     * The tooltip is the command itself, shortened so a long pipeline does
     * not make a tooltip wider than the panel. The name is what the row says;
     * this is the "what will run" a person wants before clicking.
     */
    function commandHint(command) {
        var text = String(command === undefined || command === null ? "" : command).trim()
        if (text === "") return "Run this in your default terminal"
        if (text.length > 64) text = text.slice(0, 63) + "…"
        return text
    }

    function sentence(value) {
        var lines = String(value === undefined || value === null ? "" : value).split(/\r?\n/)
        var parts = []
        for (var index = 0; index < lines.length; index++) {
            var line = lines[index].trim()
            if (line !== "") parts.push(line)
        }
        if (parts.length === 0) return ""
        var text = parts.join(" ")
        return /[.!?]$/.test(text) ? text : text + "."
    }

    function clearStatus() {
        if (root.cliMissing) return
        if (root.configError) return
        root.statusIsError = false
        root.statusDetail = ""
        root.statusText = "Run a command"
    }

    /*
     * Opening re-reads the file, so an edit made in a terminal shows up on the
     * next open rather than needing a shell restart. Closing clears the result
     * line: a failure is worth seeing until the panel is dismissed, and the
     * panel is dismissed to get it out of the way.
     */
    onOpenedChanged: {
        if (root.opened) {
            root.cursor = 0
            root.clearStatus()
            if (root.cliMissing) root.probe()
            else root.refresh()
            return
        }
        root.clearStatus()
    }

    Component.onCompleted: root.probe()

    // -- the bar icon
    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        // U+F120 is fa-terminal in the bar font (JetBrainsMono Nerd Font).
        // Written as an escape: the glyph is in the private use area and does
        // not survive being pasted into a source file as a literal character.
        text: "\uf120"
        tooltipText: "Oshelly: run a shell command"
        onPressed: function(button) {
            root.toggle()
        }
    }

    // -- the panel
    KeyboardPanel {
        id: dropdown
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: dropdown.fittedContentWidth(Style.space(320))
        contentHeight: dropdown.fittedContentHeight(col.implicitHeight, Style.space(360))

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: function(direction) { root.switchPanel(direction) }
            onMoveRequested: function(dx, dy) {
                if (dy !== 0) root.moveCursor(dy)
            }
            onActivateRequested: root.activateCursor()

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: col.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: col
                    width: parent.width
                    spacing: Style.space(8)
                    topPadding: Style.space(12)
                    bottomPadding: Style.space(12)

                    PanelHero {
                        id: hero
                        width: parent.width
                        title: "Oshelly"
                        // Rendered by the shell itself, so strip and cap first.
                        meta: root.plain(root.statusText, 80)
                        foreground: Color.foreground
                        fontFamily: Style.font.family
                        iconComponent: Component {
                            Text {
                                text: button.text
                                textFormat: Text.PlainText
                                color: root.statusIsError ? "#f44" : hero.foreground
                                font.family: hero.fontFamily
                                font.pixelSize: Style.font.displayLarge
                            }
                        }
                        /*
                         * The one control in the header. Editing the config is
                         * the thing that has to be reachable from the panel
                         * that said the file is empty or wrong, so it sits
                         * on the hero rather than at the bottom of the list.
                         */
                        trailingControl: Component {
                            Button {
                                text: "Edit"
                                bordered: true
                                enabled: root.cliPath !== "" && !actionProcess.running
                                tooltipText: "Edit the config in your default editor"
                                onClicked: root.editConfig()
                            }
                        }
                    }

                    // The hero has no room for a colour cue, so the failure is
                    // repeated here in text that can be read.
                    Text {
                        width: parent.width
                        visible: root.statusIsError
                        text: root.statusDetail
                        textFormat: Text.PlainText
                        color: "#f44"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.WordWrap
                    }

                    PanelSeparator { foreground: Color.foreground }

                    Repeater {
                        model: root.commands

                        Item {
                            id: commandRow
                            required property var modelData
                            required property int index

                            width: parent.width
                            height: Style.space(34)

                            Button {
                                id: commandButton
                                anchors.left: parent.left
                                anchors.right: closeButton.left
                                anchors.rightMargin: root.columnGap
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                bordered: true
                                enabled: !actionProcess.running
                                // A click is the ordinary use; the cursor is
                                // what makes the same row reachable by arrow
                                // keys once the panel has focus.
                                selected: commandRow.index === root.cursor
                                text: commandRow.modelData.name
                                tooltipText: root.commandHint(commandRow.modelData.command)
                                onClicked: root.launch(commandRow.modelData.name)
                            }

                            /*
                             * The power button is the per-command close
                             * setting. Selected means the terminal closes
                             * after this command; unselected means it stays
                             * open. It is a setting, so it writes through the
                             * CLI and does not launch anything.
                             */
                            Button {
                                id: closeButton
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: root.closeColumnWidth
                                bordered: true
                                enabled: !actionProcess.running
                                selected: commandRow.modelData.close === true
                                text: "\uf011"
                                tooltipText: commandRow.modelData.close === true
                                    ? "Terminal closes after this command"
                                    : "Terminal stays open after this command"
                                onClicked: root.toggleClose(commandRow.modelData)
                            }
                        }
                    }

                    /*
                     * The empty state is the one place the config syntax is
                     * worth repeating. It names the actual path, because a
                     * panel that says "no commands configured" without saying
                     * where is a panel that leaves the next step to be guessed.
                     */
                    Text {
                        width: parent.width
                        visible: root.loadedReady && !root.configError && root.commands.length === 0
                        text: "No commands configured yet.\n\n"
                            + "Add one per line to " + root.configPath + ":\n"
                            + "    Restart audio: systemctl --user restart pipewire\n\n"
                            + "Then open this panel again."
                        textFormat: Text.PlainText
                        color: Util.alpha(Color.foreground, 0.7)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        visible: root.commands.length > 0 && !root.statusIsError
                        text: "Click a command, or use the arrow keys and Enter. "
                            + "The power button closes the terminal after a command."
                        textFormat: Text.PlainText
                        color: Util.alpha(Color.foreground, 0.7)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
