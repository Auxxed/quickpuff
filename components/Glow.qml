import QtQuick
import QtQuick.Shapes
import qs.Commons

// A soft round glow: `hue` in the middle, fading to nothing at the edge.
// Drawn at 100 x 100 and sized with `scale` or a Scale transform, so moving
// or resizing it never re-tessellates.
Shape {
  id: glow

  property color hue: "white"

  width: 100
  height: 100
  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    strokeColor: "transparent"
    fillGradient: RadialGradient {
      centerX: 50; centerY: 50; centerRadius: 50
      focalX: 50; focalY: 50
      GradientStop { position: 0.0; color: glow.hue }
      GradientStop { position: 0.35; color: Util.alpha(glow.hue, glow.hue.a * 0.45) }
      GradientStop { position: 1.0; color: Util.alpha(glow.hue, 0) }
    }
    PathSvg { path: "M0,50 A50,50 0 1,0 100,50 A50,50 0 1,0 0,50 Z" }
  }
}
