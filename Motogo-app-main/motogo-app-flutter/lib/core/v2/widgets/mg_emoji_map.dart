import '../icons/mg_icon.dart';
import '../states/mg_tone.dart';

/// v2 look of the emoji the old toast / dialog code passes (design D4/D5:
/// no emoji in the v2 UI — they become line icons + a meaning tone).
(String icon, MgTone tone) mgToastLookFor(String? emoji) {
  final e = (emoji ?? '').replaceAll('️', '').trim();
  switch (e) {
    case '✓':
    case '✔':
    case '✅':
    case '👍':
      return (MgIcons.checkCircle, MgTone.ok);
    case '✗':
    case '✕':
    case '❌':
    case '🚫':
      return (MgIcons.xCircle, MgTone.err);
    case '⚠':
    case '❗':
    case '❕':
      return (MgIcons.warn, MgTone.warn);
    case '⏳':
    case '⌛':
      return (MgIcons.clock, MgTone.pending);
    case '💬':
    case '📩':
    case '✉':
      return (MgIcons.chat, MgTone.info);
    case '⭐':
    case '🌟':
      return (MgIcons.starFilled, MgTone.ok);
    case '📍':
      return (MgIcons.pin, MgTone.info);
    case '🔒':
      return (MgIcons.lock, MgTone.info);
    case '🔑':
      return (MgIcons.key, MgTone.ok);
    case '🛰':
      return (MgIcons.satellite, MgTone.info);
    default:
      return (MgIcons.info, MgTone.info);
  }
}

/// Pictographs (emoji, incl. VS16 / ZWJ sequences, skin tones, flags) and
/// the space next to them, removed from a text shown in the v2 look.
String mgStripEmoji(String s) => s
    .replaceAll(_emojiRun, ' ')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAllMapped(RegExp(r' ([.,!?:;)])'), (m) => m[1]!)
    .trim();

/// One emoji "run": a pictograph (or regional-indicator pair) with its
/// modifiers / variation selectors / ZWJ-joined parts, plus surrounding
/// spaces (collapsed to one by [mgStripEmoji]).
final RegExp _emojiRun = RegExp(
  '[ \\t]*(?:$_pict|$_flag)(?:[\\u{FE0F}\\u{20E3}\\u{1F3FB}-\\u{1F3FF}]|\\u{200D}(?:$_pict))*[\\u{FE0F}]?[ \\t]*',
  unicode: true,
);

/// Pictographs only — text symbols (→ © ™ • –) stay.
const _pict = '[\\u{1F000}-\\u{1FAFF}\\u{2600}-\\u{27BF}\\u{2B00}-\\u{2BFF}\\u{2300}-\\u{23FF}'
    '\\u{2194}-\\u{2199}\\u{21A9}\\u{21AA}\\u{25AA}\\u{25AB}\\u{25B6}\\u{25C0}\\u{25FB}-\\u{25FE}'
    '\\u{2934}\\u{2935}\\u{3030}\\u{303D}\\u{3297}\\u{3299}\\u{203C}\\u{2049}]';
const _flag = '[\\u{1F1E6}-\\u{1F1FF}]{2}';
