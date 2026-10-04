/// Invalidates queued registrations and content when authentication changes.
/// Kept independent from platform SDKs so lifecycle races are regression-tested.
class PushSession {
  String? userId;
  int generation = 0;

  int bind(String id) {
    if (userId != id) {
      generation++;
      userId = id;
    }
    return generation;
  }

  void clear() {
    generation++;
    userId = null;
  }

  bool isCurrent(String id, int version) =>
      userId == id && generation == version;
  bool acceptsRecipient(String? recipient) =>
      userId != null && recipient == userId;
}
