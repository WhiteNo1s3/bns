import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;

/// Central registry for the PC keybinds (set & forget).
///
/// One source of truth used by:
/// - `main.dart` to build the live Shortcuts map from settings
/// - the Sync & PC screen to render the checkbox rows and record new combos
/// - `IsarService` to seed the defaults
///
/// Combos are stored as lowercase strings like "ctrl+enter" or "ctrl+shift+c"
/// inside AppSettings.keybinds, so they travel in the shared .bns file.
class KeybindAction {
  final String id;
  final String label;

  const KeybindAction(this.id, this.label);
}

class Keybinds {
  /// Every action the app can bind, in the order shown to the user.
  static const List<KeybindAction> actions = [
    KeybindAction('open_today', 'Go to Today'),
    KeybindAction('mark_done', 'Mark next unfinished step done'),
    KeybindAction(
        'focus_routines', 'Jump to today\'s steps (then ↑↓, Enter, S)'),
    KeybindAction('focus_diary', 'Jump to the diary field'),
    KeybindAction('save_diary', 'Save the diary entry'),
    KeybindAction('quick_capture', 'Open quick capture'),
    KeybindAction('open_routines', 'Open routines manager'),
    KeybindAction('open_calendar', 'Open calendar'),
    KeybindAction('open_memories', 'Open memories / garden'),
    KeybindAction('open_sync', 'Open Sync & PC settings'),
  ];

  static const Map<String, String> defaults = {
    'open_today': 'ctrl+t',
    'mark_done': 'ctrl+enter',
    'focus_routines': 'ctrl+g',
    'focus_diary': 'ctrl+d',
    'save_diary': 'ctrl+shift+enter',
    'quick_capture': 'ctrl+n',
    'open_routines': 'ctrl+r',
    'open_calendar': 'ctrl+shift+c',
    'open_memories': 'ctrl+m',
    'open_sync': 'ctrl+,',
  };

  static const Map<String, bool> defaultEnabled = {
    'open_today': true,
    'mark_done': true,
    'focus_routines': true,
    'focus_diary': true,
    'save_diary': true,
    'quick_capture': true,
    'open_routines': true,
    'open_calendar': true,
    'open_memories': true,
    'open_sync': true,
  };

  static String labelFor(String id) {
    for (final a in actions) {
      if (a.id == id) return a.label;
    }
    return id;
  }

  /// Parse a stored combo string into an activator, or null if unreadable.
  /// Unreadable combos are simply skipped — a bad edit never breaks the app.
  static SingleActivator? parse(String combo) {
    final parts = combo
        .toLowerCase()
        .split('+')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    bool ctrl = false, shift = false, alt = false, meta = false;
    String? keyName;

    for (final p in parts) {
      switch (p) {
        case 'ctrl':
        case 'control':
          ctrl = true;
        case 'shift':
          shift = true;
        case 'alt':
        case 'option':
          alt = true;
        case 'cmd':
        case 'meta':
        case 'win':
          meta = true;
        default:
          keyName = p;
      }
    }

    if (keyName == null) return null;
    final key = _named[keyName];
    if (key == null) return null;

    return SingleActivator(key,
        control: ctrl, shift: shift, alt: alt, meta: meta);
  }

  /// Pretty display: "ctrl+shift+enter" -> "Ctrl+Shift+Enter".
  static String pretty(String combo) {
    return combo
        .split('+')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .map((p) => p.length == 1
            ? p.toUpperCase()
            : '${p[0].toUpperCase()}${p.substring(1)}')
        .join('+');
  }

  /// Build a combo string from a key event (used by the press-to-record UI).
  /// Returns null while only modifiers are held.
  static String? comboFromEvent(KeyEvent event) {
    final key = event.logicalKey;
    if (_isModifier(key)) return null;
    final name = nameForKey(key);
    if (name == null) return null;

    final hw = HardwareKeyboard.instance;
    final parts = <String>[
      if (hw.isControlPressed) 'ctrl',
      if (hw.isMetaPressed) 'cmd',
      if (hw.isAltPressed) 'alt',
      if (hw.isShiftPressed) 'shift',
      name,
    ];
    return parts.join('+');
  }

  static bool _isModifier(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  static String? nameForKey(LogicalKeyboardKey key) {
    // Letters, digits, punctuation come back as a single-char label.
    final label = key.keyLabel;
    if (label.length == 1) {
      final lower = label.toLowerCase();
      if (_named.containsKey(lower)) return lower;
    }
    for (final e in _named.entries) {
      if (e.value == key && e.key.length > 1) return e.key;
    }
    return null;
  }

  static final Map<String, LogicalKeyboardKey> _named = {
    'a': LogicalKeyboardKey.keyA,
    'b': LogicalKeyboardKey.keyB,
    'c': LogicalKeyboardKey.keyC,
    'd': LogicalKeyboardKey.keyD,
    'e': LogicalKeyboardKey.keyE,
    'f': LogicalKeyboardKey.keyF,
    'g': LogicalKeyboardKey.keyG,
    'h': LogicalKeyboardKey.keyH,
    'i': LogicalKeyboardKey.keyI,
    'j': LogicalKeyboardKey.keyJ,
    'k': LogicalKeyboardKey.keyK,
    'l': LogicalKeyboardKey.keyL,
    'm': LogicalKeyboardKey.keyM,
    'n': LogicalKeyboardKey.keyN,
    'o': LogicalKeyboardKey.keyO,
    'p': LogicalKeyboardKey.keyP,
    'q': LogicalKeyboardKey.keyQ,
    'r': LogicalKeyboardKey.keyR,
    's': LogicalKeyboardKey.keyS,
    't': LogicalKeyboardKey.keyT,
    'u': LogicalKeyboardKey.keyU,
    'v': LogicalKeyboardKey.keyV,
    'w': LogicalKeyboardKey.keyW,
    'x': LogicalKeyboardKey.keyX,
    'y': LogicalKeyboardKey.keyY,
    'z': LogicalKeyboardKey.keyZ,
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
    'enter': LogicalKeyboardKey.enter,
    'return': LogicalKeyboardKey.enter,
    'space': LogicalKeyboardKey.space,
    'tab': LogicalKeyboardKey.tab,
    'esc': LogicalKeyboardKey.escape,
    'escape': LogicalKeyboardKey.escape,
    ',': LogicalKeyboardKey.comma,
    'comma': LogicalKeyboardKey.comma,
    '.': LogicalKeyboardKey.period,
    'period': LogicalKeyboardKey.period,
    '-': LogicalKeyboardKey.minus,
    'minus': LogicalKeyboardKey.minus,
    '=': LogicalKeyboardKey.equal,
    'equal': LogicalKeyboardKey.equal,
    '/': LogicalKeyboardKey.slash,
    'slash': LogicalKeyboardKey.slash,
    ';': LogicalKeyboardKey.semicolon,
    'semicolon': LogicalKeyboardKey.semicolon,
    "'": LogicalKeyboardKey.quote,
    'quote': LogicalKeyboardKey.quote,
    '`': LogicalKeyboardKey.backquote,
    'backquote': LogicalKeyboardKey.backquote,
    '[': LogicalKeyboardKey.bracketLeft,
    ']': LogicalKeyboardKey.bracketRight,
    '\\': LogicalKeyboardKey.backslash,
    'backslash': LogicalKeyboardKey.backslash,
    'up': LogicalKeyboardKey.arrowUp,
    'down': LogicalKeyboardKey.arrowDown,
    'left': LogicalKeyboardKey.arrowLeft,
    'right': LogicalKeyboardKey.arrowRight,
    'delete': LogicalKeyboardKey.delete,
    'del': LogicalKeyboardKey.delete,
    'backspace': LogicalKeyboardKey.backspace,
    'home': LogicalKeyboardKey.home,
    'end': LogicalKeyboardKey.end,
    'pageup': LogicalKeyboardKey.pageUp,
    'pagedown': LogicalKeyboardKey.pageDown,
    'f1': LogicalKeyboardKey.f1,
    'f2': LogicalKeyboardKey.f2,
    'f3': LogicalKeyboardKey.f3,
    'f4': LogicalKeyboardKey.f4,
    'f5': LogicalKeyboardKey.f5,
    'f6': LogicalKeyboardKey.f6,
    'f7': LogicalKeyboardKey.f7,
    'f8': LogicalKeyboardKey.f8,
    'f9': LogicalKeyboardKey.f9,
    'f10': LogicalKeyboardKey.f10,
    'f11': LogicalKeyboardKey.f11,
    'f12': LogicalKeyboardKey.f12,
  };
}
