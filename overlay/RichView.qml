import QtQuick
import qs.services

// The rich card (docs/SPEC.md sections 4 and 7, decision D1): a 72 px card
// above the note region with a thumbnail of the notification's image, for
// the `screenshot` app only. It lies in the upper 72 px of the overlay,
// which exist for it alone.
//
// NoteView decides when the card rises and falls and sets `up` (0 hidden
// behind the strip, 1 fully up). The card slides out from behind the
// strip: this item clips at the strip's top edge. It draws from `snap`,
// which NoteView latches when the card starts to rise, so the card keeps
// its picture while it falls after the notification closed.
//
// Clicks and hover on the card count as clicks and hover on the note.
Item {
    id: root

    // The note line's snapshot: `picture` (an image URL) and `background`.
    property var snap: null
    property real up: 0
    // Device pixel ratio of the window: the thumbnail loads at the
    // physical size it is drawn at.
    property real dpr: 1
    // The widest the card may be (the note region's width).
    property real maxWidth: 0

    // The picture loaded: the card may rise.
    readonly property bool ready: snap !== null && thumb.status === Image.Ready && thumb.width > 0
    readonly property bool hovered: mouse.containsMouse
    // What the overlay's input mask adds for the card: the part above the
    // strip, nothing while the card is down.
    readonly property Item hitArea: hit
    readonly property alias card: card

    signal clicked(int button)

    readonly property int padding: 4
    readonly property real thumbHeight: Theme.cardHeight - 2 * padding
    // The thumbnail's width at the picture's aspect ratio, capped.
    readonly property real naturalWidth: thumb.implicitHeight > 0 ? Math.round(thumbHeight * thumb.implicitWidth / thumb.implicitHeight) : 0

    width: card.width
    height: Theme.cardHeight
    clip: true

    Rectangle {
        id: card

        y: Math.round(root.height * (1 - root.up))
        width: root.ready ? thumb.width + 2 * root.padding : 0
        height: root.height
        color: Theme[root.snap ? root.snap.background : "base01"]
        visible: root.up > 0

        Image {
            id: thumb

            x: root.padding
            y: root.padding
            width: Math.max(0, Math.min(root.naturalWidth, root.maxWidth - 2 * root.padding))
            height: root.thumbHeight
            fillMode: Image.PreserveAspectFit
            smooth: true
            // Decoding a screenshot blocks for 150 to 350 ms: off the GUI thread.
            asynchronous: true
            source: root.snap ? root.snap.picture : ""
            sourceSize.height: Math.round(root.thumbHeight * root.dpr)
        }
    }

    Item {
        id: hit
        y: card.y
        width: root.up > 0 ? card.width : 0
        height: root.height - card.y
    }

    MouseArea {
        id: mouse
        anchors.fill: hit
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => root.clicked(event.button)
    }
}
