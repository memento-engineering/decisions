/// Tier-2 assets and command composition for the decisions register.
library;

import 'package:decisions/decisions.dart'
    show decisionEntrySpecMaximum, decisionEntrySpecMinimum;

export 'package:decisions/decisions.dart'
    show
        DecisionIndex,
        DecisionRegisterSnapshot,
        DecisionRegisterUnion,
        DecisionSearchCommand,
        DecisionSearchFilters,
        DecisionSearchHit,
        DecisionSearchResult,
        DecisionSearchService,
        DecisionSearchStatusFilter,
        DecisionsCommand,
        IndexCommand,
        RegisterPathResolver,
        decisionSearchOutputSpec,
        decisionSearchSnippetCap,
        matchesDecisionSurface;
export 'src/assets/grid_asset_pack.dart';
export 'src/command.dart';

/// Lowest decision-entry spec this adapter reads.
const int decisionsGridAssetsReadSpecMinimum = decisionEntrySpecMinimum;

/// Highest decision-entry spec this adapter reads.
const int decisionsGridAssetsReadSpecMaximum = decisionEntrySpecMaximum;

/// Decision-entry specs this read-only adapter writes.
const Set<int> decisionsGridAssetsWrittenDecisionSpecs = <int>{};
