.pragma library

// Built from strings, so this file stays ASCII: U+2028 and U+2029 can't sit
// in a regex literal (QML's lexer reads them as line breaks).
var markup = new RegExp("[<>&]", "g")
var bidi = new RegExp("[\\u061c\\u200e\\u200f\\u202a-\\u202e\\u2066-\\u2069]", "g")
var lineBreaks = new RegExp("\\r\\n?|[\\u2028\\u2029]", "g")
var controlsButNewline = new RegExp("[\\u0000-\\u0009\\u000b-\\u001f\\u007f-\\u009f]", "g")
var controls = new RegExp("[\\u0000-\\u001f\\u007f-\\u009f\\u2028\\u2029]", "g")

// Text for components the shell draws itself (the bar button and its
// tooltip, ConfirmDialog, PanelSectionHeader). Those use Text.AutoText, which
// draws a string that looks like markup as rich text, and rich text can load
// images. So: no < > &, no control or bidi-override characters, and a hard
// length cap. `lines` keeps newlines (tooltips).
function plain(value, max, lines) {
  var s = value === undefined || value === null ? "" : String(value)
  s = s.replace(markup, "").replace(bidi, "")
  if (lines) s = s.replace(lineBreaks, "\n").replace(controlsButNewline, " ")
  else s = s.replace(controls, " ")
  var limit = max > 0 ? max : 120
  if (s.length > limit) {
    var cut = limit
    // Don't split a surrogate pair.
    var c = s.charCodeAt(cut - 1)
    if (c >= 0xd800 && c <= 0xdbff) cut--
    s = s.slice(0, cut)
  }
  return s
}

// An array of at most `max` items, or null: too long is refused, not cut
// down, since a list that size didn't come from the daemon.
function list(value, max) {
  if (!Array.isArray(value)) return []
  return value.length <= max ? value : null
}
