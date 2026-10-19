import QtQuick
import QtQuick.Shapes
import qs.Commons

// Light running round a rounded rectangle's edge: a short comet (a soft
// glow, a body and a bright core, their heads together) travelling the
// outline, `count` of them evenly spaced. Drawn as dashed strokes of one
// path, so it's one continuous line of light, not a trail of dots.
//
// Fill the item it runs round; `radius` is that item's corner radius.
Shape {
  id: runner

  property color hue: "white"
  property real radius: 0
  property bool running: false
  property int count: 1
  // One lap, in ms.
  property int duration: 1700
  // The comet's length along the edge, in px.
  property real length: 64
  property real thickness: 1.5
  // Draw the whole comet inside the outline (for items that clip), rather
  // than centred on it.
  property bool inside: false

  // How far round the head is, in px from the top-left corner.
  property real head: 0
  readonly property real glowW: thickness * (inside ? 2.5 : 4)
  readonly property real inset: inside ? glowW / 2 : thickness / 2
  readonly property real r: Math.max(0, Math.min(radius - inset, width / 2 - inset, height / 2 - inset))
  readonly property real perimeter: Math.max(1, 2 * (width + height - 4 * inset) - (8 - 2 * Math.PI) * r)
  readonly property real spacing: perimeter / Math.max(1, count)

  visible: running
  preferredRendererType: Shape.CurveRenderer

  NumberAnimation on head {
    running: runner.running && runner.visible
    loops: Animation.Infinite
    from: 0
    to: runner.perimeter
    duration: runner.duration
  }

  // A dashed stroke whose dash ends at the head: `len` long, `w` wide.
  component Trail: ShapePath {
    property real len: 0
    property real w: 1
    strokeWidth: w
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap
    strokeStyle: ShapePath.DashLine
    dashPattern: [Math.max(0.01, len / w), Math.max(0.01, (runner.spacing - len) / w)]
    dashOffset: (len - runner.head) / w
    PathRectangle {
      x: runner.inset
      y: runner.inset
      width: runner.width - 2 * runner.inset
      height: runner.height - 2 * runner.inset
      radius: runner.r
    }
  }

  Trail { len: runner.length; w: runner.glowW; strokeColor: Util.alpha(runner.hue, 0.16) }
  Trail { len: runner.length * 0.6; w: runner.thickness * 2; strokeColor: Util.alpha(Qt.lighter(runner.hue, 1.25), 0.5) }
  Trail { len: runner.length * 0.28; w: runner.thickness; strokeColor: Qt.tint(runner.hue, Util.alpha("#ffffff", 0.7)) }
}
