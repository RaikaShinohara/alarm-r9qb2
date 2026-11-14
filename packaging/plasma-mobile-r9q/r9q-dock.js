// r9q-dock: a desktop Plasma panel on every external screen (screen 0 is the
// phone's own panel). Run by r9q-dock through PlasmaShell.evaluateScript.
for (var s = 1; s < screenCount; s++) {
    var found = false;
    var ps = panels();
    for (var i = 0; i < ps.length; i++) {
        if (ps[i].type === "org.kde.panel" && ps[i].screen === s) {
            found = true;
        }
    }
    if (found) {
        continue;
    }
    var panel = new Panel("org.kde.panel", s);
    panel.location = "bottom";
    panel.height = 2 * Math.floor(gridUnit * 2.5 / 2);
    var widgets = ["org.kde.plasma.kickoff", "org.kde.plasma.icontasks",
                   "org.kde.plasma.marginsseparator", "org.kde.plasma.systemtray",
                   "org.kde.plasma.digitalclock", "org.kde.plasma.showdesktop"];
    for (var w = 0; w < widgets.length; w++) {
        panel.addWidget(widgets[w]);
    }
    print("r9q-dock: panel on screen " + s + " -> " + panel.screen);
}
