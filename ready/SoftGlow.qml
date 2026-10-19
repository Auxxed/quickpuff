import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import qs.Commons
import "../components"

Shape {
  id: glow

  property color hue: "white"

  width: 100
  height: 100

  ShapePath {
    strokeColor: "transparent"
    fillGradient: RadialGradient {
      centerX: 50; centerY: 50; centerRadius: 50
      focalX: 50; focalY: 50
      GradientStop { position: 0.0; color: glow.hue }
      // Half the centre's alpha, not a flat 0.5: a fainter glow had a
      // brighter ring than middle, and every soft glow came out a donut.
      GradientStop { position: 0.3; color: Util.alpha(glow.hue, glow.hue.a * 0.5) }
      GradientStop { position: 1.0; color: Util.alpha(glow.hue, 0) }
    }
    PathSvg { path: "M0,50 A50,50 0 1,0 100,50 A50,50 0 1,0 0,50 Z" }
  }
}
