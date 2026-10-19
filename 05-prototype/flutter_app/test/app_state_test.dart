import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medic_app/app/state/app_state.dart';

void main() {
  test('selecting a valid profile persists and rejects an unknown ID', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(activeProfileProvider).id, 'self');
    container.read(activeProfileIdProvider.notifier).select('mother');
    expect(container.read(activeProfileProvider).name, 'Phạm Thị Lan');
    expect(
      () => container.read(activeProfileIdProvider.notifier).select('missing'),
      throwsArgumentError,
    );
    expect(container.read(activeProfileProvider).id, 'mother');
  });

  test(
    'notification reads are immutable, idempotent and update the unread count',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final initial = container.read(notificationFeedProvider);
      expect(container.read(unreadCountProvider), 2);
      final controller = container.read(notificationFeedProvider.notifier);
      controller.markRead('welcome');
      expect(container.read(unreadCountProvider), 1);
      expect(initial.first.isRead, isFalse);
      controller.markRead('welcome');
      controller.markRead('missing');
      expect(container.read(unreadCountProvider), 1);
      controller.markAllRead();
      expect(container.read(unreadCountProvider), 0);
      expect(
        container
            .read(notificationFeedProvider)
            .every((notice) => notice.isRead),
        isTrue,
      );
    },
  );

  test('independent sessions do not share profile or notification changes', () {
    final first = ProviderContainer();
    final second = ProviderContainer();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    first.read(activeProfileIdProvider.notifier).select('mother');
    first.read(notificationFeedProvider.notifier).markAllRead();
    expect(second.read(activeProfileProvider).id, 'self');
    expect(second.read(unreadCountProvider), 2);
  });
}
