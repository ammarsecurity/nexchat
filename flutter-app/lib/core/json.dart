// The API mixes camelCase and PascalCase depending on the serializer; read both like the Vue code does.
import 'time.dart';

typedef Json = Map<String, dynamic>;

extension JsonPick on Map<dynamic, dynamic> {
  dynamic v(String key) {
    final a = this[key];
    if (a != null) return a;
    return this[key[0].toUpperCase() + key.substring(1)];
  }

  String? s(String key) {
    final x = v(key);
    return x == null ? null : '$x';
  }

  String str(String key) => s(key) ?? '';

  bool b(String key) {
    final x = v(key);
    return x == true || x == 'true' || x == 1;
  }

  int i(String key) {
    final x = v(key);
    if (x is int) return x;
    if (x is num) return x.toInt();
    return int.tryParse('$x') ?? 0;
  }

  /// UTC instant from API (display via format.dart → Iraq UTC+3).
  DateTime? date(String key) {
    final x = s(key);
    if (x == null) return null;
    return parseApiDate(x);
  }
}

List<Json> asJsonList(Object? data) {
  if (data is List) return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  if (data is Map) {
    final items = data['items'] ?? data['Items'] ?? data['data'];
    if (items is List) return asJsonList(items);
  }
  return [];
}
