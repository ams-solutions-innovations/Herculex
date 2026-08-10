/// Metadata for one bundled preset program in the marketplace catalog
/// (`assets/programs/catalog.json`). The full prescription lives in the
/// sibling CSV named by [file]; this is just enough to render a browse card
/// and drive search/filtering without parsing every program on the list.
class PresetProgramMeta {
  final String id;
  final String name;
  final String file;
  final String description;
  final int weeks;
  final int daysPerWeek;
  final String level; // beginner | intermediate | advanced
  final String goal; // strength | hypertrophy | general
  final String periodization;

  const PresetProgramMeta({
    required this.id,
    required this.name,
    required this.file,
    required this.description,
    required this.weeks,
    required this.daysPerWeek,
    required this.level,
    required this.goal,
    required this.periodization,
  });

  factory PresetProgramMeta.fromJson(Map<String, dynamic> json) {
    return PresetProgramMeta(
      id: json['id'] as String,
      name: json['name'] as String,
      file: json['file'] as String,
      description: json['description'] as String,
      weeks: json['weeks'] as int,
      daysPerWeek: json['daysPerWeek'] as int,
      level: json['level'] as String,
      goal: json['goal'] as String,
      periodization: json['periodization'] as String,
    );
  }
}
