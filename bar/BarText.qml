import QtQuick
import qs.services

// A text line of the bar: bar font, bar height, vertically centered like
// waybar's labels (0.1em top padding). Plain text unless told otherwise.
Text {
    height: Theme.barHeight
    topPadding: 1
    verticalAlignment: Text.AlignVCenter
    textFormat: Text.PlainText
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    font.letterSpacing: Theme.letterSpacing
}
