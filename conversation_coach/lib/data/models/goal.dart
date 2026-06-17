import 'dart:convert';

/// A weighted dimension within a [Rubric] (e.g. "Listening ratio", weight 0.2).
class RubricDimension {
  final String name;
  final double weight;
  final String description;

  const RubricDimension({
    required this.name,
    required this.weight,
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'weight': weight,
        'description': description,
      };

  factory RubricDimension.fromJson(Map<String, dynamic> j) => RubricDimension(
        name: j['name'] as String,
        weight: (j['weight'] as num).toDouble(),
        description: (j['description'] as String?) ?? '',
      );
}

/// F-GOAL-02 / F-GOAL-03 — a goal maps to a rubric of weighted dimensions.
class Rubric {
  final String id;
  final String name;
  final List<RubricDimension> dimensions;

  const Rubric({
    required this.id,
    required this.name,
    required this.dimensions,
  });

  /// Weights normalised so the goal score is a clean weighted average even if
  /// the author's weights don't sum to exactly 1.0.
  Map<String, double> normalisedWeights() {
    final total = dimensions.fold<double>(0, (s, d) => s + d.weight);
    if (total <= 0) {
      final even = dimensions.isEmpty ? 0.0 : 1.0 / dimensions.length;
      return {for (final d in dimensions) d.name: even};
    }
    return {for (final d in dimensions) d.name: d.weight / total};
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'dimensions': jsonEncode(dimensions.map((d) => d.toJson()).toList()),
      };

  factory Rubric.fromMap(Map<String, dynamic> m) => Rubric(
        id: m['id'] as String,
        name: m['name'] as String,
        dimensions: (jsonDecode(m['dimensions'] as String) as List)
            .map((e) => RubricDimension.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// F-GOAL-01 — a goal chosen per session, from a template library or custom.
class Goal {
  final String id;

  /// Null for built-in templates; a user id for custom goals.
  final String? userId;
  final String name;
  final String description;
  final String rubricId;
  final bool isTemplate;

  const Goal({
    required this.id,
    required this.userId,
    required this.name,
    required this.description,
    required this.rubricId,
    required this.isTemplate,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'name': name,
        'description': description,
        'rubricId': rubricId,
        'isTemplate': isTemplate ? 1 : 0,
      };

  factory Goal.fromMap(Map<String, dynamic> m) => Goal(
        id: m['id'] as String,
        userId: m['userId'] as String?,
        name: m['name'] as String,
        description: (m['description'] as String?) ?? '',
        rubricId: m['rubricId'] as String,
        isTemplate: (m['isTemplate'] as int) == 1,
      );
}
