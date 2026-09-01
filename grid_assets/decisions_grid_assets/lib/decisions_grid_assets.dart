/// Tier-2 assets and command composition for the decisions register.
library;

import 'package:decisions/decisions.dart'
    show decisionEntrySpecMaximum, decisionEntrySpecMinimum;

export 'package:decisions/decisions.dart'
    show DecisionIndex, DecisionsCommand, IndexCommand, RegisterPathResolver;
export 'src/command.dart';

/// Lowest decision-entry spec this adapter reads.
const int decisionsGridAssetsReadSpecMinimum = decisionEntrySpecMinimum;

/// Highest decision-entry spec this adapter reads.
const int decisionsGridAssetsReadSpecMaximum = decisionEntrySpecMaximum;

/// Decision-entry specs this read-only adapter writes.
const Set<int> decisionsGridAssetsWrittenDecisionSpecs = <int>{};
