import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:test/test.dart';

const _selfHostedRegister = '../../../docs/decisions';
const _fixtureRegister = 'test/fixtures/graph_register';
const _danglingRegister = 'test/fixtures/dangling_register';

void main() {
  group('DecisionGraph over a fixture register', () {
    late DecisionGraph graph;

    setUpAll(() {
      graph = DecisionGraph(readRegister(_fixtureRegister));
    });

    test('keeps updates and obsoletes distinct', () {
      final update = graph
          .outgoingFrom('amendment', kind: DecisionEdgeKind.updates)
          .single;
      final obsolete = graph
          .outgoingFrom('replacement', kind: DecisionEdgeKind.obsoletes)
          .single;

      expect(update.target.slug, 'original');
      expect(update.targetReference, 'A1');
      expect(obsolete.target.slug, 'amendment');
      expect(graph.updatedBy('original').map((entry) => entry.slug), [
        'amendment',
      ]);
      expect(graph.obsoletedBy('amendment').map((entry) => entry.slug), [
        'replacement',
      ]);
      expect(graph.forceOf('original'), DecisionForce.binding);
      expect(graph.isBinding('original'), isTrue);
      expect(graph.forceOf('amendment'), DecisionForce.superseded);
      expect(graph.isBinding('amendment'), isFalse);
      expect(graph.edges, hasLength(2));
    });

    test('retains cross-register references as pending edges', () {
      final pending = graph.pendingEdges.single;

      expect(pending.source.slug, 'amendment');
      expect(pending.targetReference, 'other_repo#foreign-rule');
      expect(pending.kind, DecisionEdgeKind.updates);
      expect(graph.pendingFrom('amendment'), contains(same(pending)));
    });

    test('resolves slug and legacy id to the same entry', () {
      expect(graph.entry('A1'), same(graph.entry('original')));
      expect(graph.entry('A1').bead, 'dec-original');
      expect(graph.entry('original').legacyId, 'A1');
      expect(graph.findEntry('A1'), same(graph.entry('original')));
      expect(graph.findEntry('missing'), isNull);
    });

    test('rejects unresolved local references loudly', () {
      expect(
        () => DecisionGraph(readRegister(_danglingRegister)),
        throwsA(
          isA<DecisionGraphException>().having(
            (error) => error.message,
            'message',
            allOf(contains('dangling-source'), contains('missing-local')),
          ),
        ),
      );
    });

    test('does not mutate entries or fixture files', () {
      final files =
          Directory(_fixtureRegister).listSync().whereType<File>().toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      final before = {
        for (final file in files) file.path: file.readAsStringSync(),
      };
      final entries = readRegister(_fixtureRegister);
      final amendment = entries.singleWhere(
        (entry) => entry.slug == 'amendment',
      );
      final authoredUpdates = List<String>.of(amendment.updates);
      final localGraph = DecisionGraph(entries);

      expect(localGraph.forceOf('amendment'), DecisionForce.superseded);
      expect(amendment.status, 'accepted');
      expect(amendment.updates, authoredUpdates);
      expect({
        for (final file in files) file.path: file.readAsStringSync(),
      }, equals(before));
    });
  });

  test('self-hosted register reports three updates and binding force', () {
    final graph = DecisionGraph(readRegister(_selfHostedRegister));
    final updatedBy = graph
        .updatedBy('the-decision-register')
        .map((entry) => entry.slug)
        .toList();

    expect(updatedBy, hasLength(3));
    expect(
      updatedBy,
      unorderedEquals([
        'madr-profile',
        'entry-identity',
        'spec-and-artifact-versioning',
      ]),
    );
    expect(graph.forceOf('the-decision-register'), DecisionForce.binding);
    expect(graph.isBinding('the-decision-register'), isTrue);
  });
}
