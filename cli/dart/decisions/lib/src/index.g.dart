// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'index.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Map<String, dynamic> _$IndexedDecisionEdgeToJson(
  IndexedDecisionEdge instance,
) => <String, dynamic>{
  'kind': _$DecisionEdgeKindEnumMap[instance.kind]!,
  'reference': instance.reference,
  'resolution': _$DecisionIndexEdgeResolutionEnumMap[instance.resolution]!,
  'targetRegister': ?instance.targetRegister,
  'targetSlug': ?instance.targetSlug,
};

const _$DecisionEdgeKindEnumMap = {
  DecisionEdgeKind.obsoletes: 'obsoletes',
  DecisionEdgeKind.updates: 'updates',
};

const _$DecisionIndexEdgeResolutionEnumMap = {
  DecisionIndexEdgeResolution.resolved: 'resolved',
  DecisionIndexEdgeResolution.dangling: 'dangling',
};

Map<String, dynamic> _$IndexedDecisionToJson(IndexedDecision instance) =>
    <String, dynamic>{
      'originRegister': instance.originRegister,
      'originPath': instance.originPath,
      'slug': instance.slug,
      'status': instance.status,
      'surfaces': instance.surfaces,
      'edges': instance.edges.map((e) => e.toJson()).toList(),
    };

Map<String, dynamic> _$DecisionIndexToJson(DecisionIndex instance) =>
    <String, dynamic>{
      'spec': instance.spec,
      'decisions': instance.decisions.map((e) => e.toJson()).toList(),
    };
