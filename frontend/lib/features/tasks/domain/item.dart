import 'dart:convert';

class Item {
  final String id;
  final String kind;
  final int version;
  final Map<String, dynamic> data;
  Item(this.id, this.kind, this.version, Map<String, dynamic> value)
    : data = Map.unmodifiable(value);
  String get title => data['title'] as String? ?? '';
  bool get deleted => data['deleted_at'] != null;
  bool get completed => data['completed'] == true;
  String get notes => data['notes'] as String? ?? '';
  String? get dueDate => data['due_date'] as String?;
  String encode() => jsonEncode(data);
}
