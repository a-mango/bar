pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Notification server. M0 version: it owns org.freedesktop.Notifications and
// logs what arrives. Nothing is tracked, so the server closes each
// notification as soon as the handler returns. M1 adds tracking, the queue,
// the timers, DND and history.
Singleton {
    id: root

    property int received: 0

    NotificationServer {
        onNotification: n => {
            root.received += 1;
            console.info("notification", n.id, n.appName, n.summary, JSON.stringify(n.hints));
        }
    }
}
