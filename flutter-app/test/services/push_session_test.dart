import 'package:flutter_test/flutter_test.dart';
import 'package:nexchat/services/push_session.dart';

void main() {
  test(
    'PUSH01 logout invalidates registrations already queued for old account',
    () {
      final session = PushSession();
      final old = session.bind('a');
      expect(session.isCurrent('a', old), isTrue);
      session.clear();
      expect(session.isCurrent('a', old), isFalse);
      expect(session.acceptsRecipient('a'), isFalse);
      expect(session.acceptsRecipient(null), isFalse);
    },
  );

  test('PUSH01 switching account suppresses old-account content', () {
    final session = PushSession();
    final old = session.bind('a');
    final current = session.bind('b');
    expect(session.isCurrent('a', old), isFalse);
    expect(session.isCurrent('b', current), isTrue);
    expect(session.acceptsRecipient('a'), isFalse);
    expect(session.acceptsRecipient('b'), isTrue);
    expect(session.acceptsRecipient(null), isFalse);
    expect(session.acceptsRecipient(''), isFalse);
  });

  test('PUSH03 resume does not invalidate current account token replay', () {
    final session = PushSession();
    final version = session.bind('a');
    expect(session.bind('a'), version);
    expect(session.isCurrent('a', version), isTrue);
  });

  test(
    'PUSH01 logout/login same user cannot revive previous async callback',
    () {
      final session = PushSession();
      final old = session.bind('a');
      session.clear();
      final current = session.bind('a');
      expect(current, isNot(old));
      expect(session.isCurrent('a', old), isFalse);
    },
  );
}
