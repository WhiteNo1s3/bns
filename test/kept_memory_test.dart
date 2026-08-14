import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/kept_memory.dart';
import 'package:bns/core/models/quick_capture.dart';

QuickCapture _cap({
  String id = '1',
  MemoryLevel level = MemoryLevel.quick,
  List<String> tags = const [],
  DateTime? deletedAt,
  String? text,
  String? transcript,
  String? contextNote,
}) {
  return QuickCapture(
    id: id,
    at: DateTime(2026, 8, 14, 10),
    memoryLevel: level,
    tags: tags,
    deletedAt: deletedAt,
    text: text,
    transcript: transcript,
    contextNote: contextNote,
  );
}

void main() {
  test('a recorded quick note is a visible memory', () {
    final c = _cap(level: MemoryLevel.quick, text: 'I went to the shop');
    expect(isVisibleMemory(c), isTrue);
    expect(visibleMemories([c]).map((m) => m.id), ['1']);
  });

  test('remember and memorize are visible', () {
    expect(isVisibleMemory(_cap(level: MemoryLevel.remember, text: 'a')), isTrue);
    expect(isVisibleMemory(_cap(level: MemoryLevel.memorize, text: 'b')), isTrue);
  });

  test('trashed items stay out of the living list', () {
    final c = _cap(
      level: MemoryLevel.remember,
      text: 'gone',
      deletedAt: DateTime(2026, 8, 14),
    );
    expect(isVisibleMemory(c), isFalse);
    expect(visibleMemories([c]), isEmpty);
  });

  test('mad-vents stay hidden unless includeMad', () {
    final vent = _cap(
      level: MemoryLevel.quick,
      tags: const ['mad-vent'],
      text: 'I am furious',
    );
    expect(isVisibleMemory(vent), isFalse);
    expect(isVisibleMemory(vent, includeMad: true), isTrue);
    expect(visibleMemories([vent]), isEmpty);
    expect(visibleMemories([vent], includeMad: true).single.id, '1');
  });

  test('memoryWords prefers typed text, then transcript, then context', () {
    expect(
      memoryWords(_cap(text: ' typed ', transcript: 'heard', contextNote: 'why')),
      'typed',
    );
    expect(
      memoryWords(_cap(transcript: ' heard ', contextNote: 'why')),
      'heard',
    );
    expect(memoryWords(_cap(contextNote: ' why ')), 'why');
    expect(memoryWords(_cap()), '');
  });

  test('default kept level is remember so Save cannot vanish', () {
    expect(defaultKeptLevel, MemoryLevel.remember);
  });

  test('voice-only quick note is still a memory the person can open', () {
    final c = _cap(level: MemoryLevel.quick, text: null);
    expect(isVisibleMemory(c), isTrue);
    expect(memoryWords(c), isEmpty);
  });
}
