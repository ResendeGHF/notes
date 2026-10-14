import 'package:flutter_test/flutter_test.dart';
import 'package:saber/pages/editor/editor.dart';

void main() {
  group('normalizeTabPath', () {
    test('strips note extensions', () {
      expect(EditorTabSession.normalizeTabPath('/Work/Note.sbn2'), '/Work/Note');
      expect(EditorTabSession.normalizeTabPath('/Work/Note.sbn'), '/Work/Note');
      expect(
        EditorTabSession.normalizeTabPath('/Work/Note.SBN2'),
        '/Work/Note.SBN2',
      );
    });

    test('ensures a leading slash', () {
      expect(EditorTabSession.normalizeTabPath('Work/Note'), '/Work/Note');
      expect(EditorTabSession.normalizeTabPath('/Work/Note'), '/Work/Note');
    });

    test('normalizes backslashes', () {
      expect(
        EditorTabSession.normalizeTabPath('\\Work\\Note.sbn2'),
        '/Work/Note',
      );
    });
  });

  group('indexOfPath', () {
    test('matches across path forms so an open note activates its tab', () {
      final open = <String?>['/Work/Alpha', '/Beta.sbn2', '/Work/Gamma.sbn'];
      expect(EditorTabSession.indexOfPath(open, '/Work/Alpha'), 0);
      expect(EditorTabSession.indexOfPath(open, '/Beta'), 1);
      expect(EditorTabSession.indexOfPath(open, '/Beta.sbn2'), 1);
      expect(EditorTabSession.indexOfPath(open, 'Work/Gamma'), 2);
    });

    test('returns -1 for unknown notes and skips null entries', () {
      final open = <String?>['/Work/Alpha', null, '', '/Beta'];
      expect(EditorTabSession.indexOfPath(open, '/Work/Delta'), -1);
      expect(EditorTabSession.indexOfPath(open, '/Other'), -1);
      expect(EditorTabSession.indexOfPath([], '/Work/Alpha'), -1);
    });
  });

  group('replace/clear', () {
    tearDown(EditorTabSession.clear);

    test('replace stores tabs and the active index', () {
      EditorTabSession.replace(
        [
          PersistedEditorTab(path: '/A', noteId: 'id-a'),
          PersistedEditorTab(path: '/B'),
        ],
        1,
      );
      expect(EditorTabSession.tabs.map((t) => t.path), ['/A', '/B']);
      expect(EditorTabSession.tabs.first.noteId, 'id-a');
      expect(EditorTabSession.activeIndex, 1);
    });

    test('clear empties the session for single-tab back navigation', () {
      EditorTabSession.replace([PersistedEditorTab(path: '/A')], 0);
      EditorTabSession.clear();
      expect(EditorTabSession.tabs, isEmpty);
      expect(EditorTabSession.activeIndex, 0);
    });
  });
}
