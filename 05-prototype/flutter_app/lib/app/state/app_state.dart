import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local demonstration data. No medical records, authentication or disk storage.
class PreviewProfile {
  const PreviewProfile({
    required this.id,
    required this.name,
    required this.birthYear,
    required this.relationship,
    this.birthDate,
  });
  final String id;
  final String name;
  final int birthYear;
  final String relationship;
  final DateTime? birthDate;
}

final profileCatalogProvider =
    NotifierProvider<ProfileCatalogController, List<PreviewProfile>>(
      ProfileCatalogController.new,
    );

class ProfileCatalogController extends Notifier<List<PreviewProfile>> {
  @override
  List<PreviewProfile> build() => const [
    PreviewProfile(
      id: 'self',
      name: 'Phạm Văn Hòa',
      birthYear: 1966,
      relationship: 'Bản thân',
    ),
    PreviewProfile(
      id: 'mother',
      name: 'Phạm Thị Lan',
      birthYear: 1948,
      relationship: 'Mẹ',
    ),
    PreviewProfile(
      id: 'child',
      name: 'Phạm Minh An',
      birthYear: 2017,
      relationship: 'Cháu',
    ),
  ];

  void add(PreviewProfile profile) {
    if (state.any((value) => value.id == profile.id)) return;
    state = List.unmodifiable([...state, profile]);
  }
}

final activeProfileIdProvider =
    NotifierProvider<ActiveProfileController, String>(
      ActiveProfileController.new,
    );

class ActiveProfileController extends Notifier<String> {
  @override
  String build() => ref.read(profileCatalogProvider).first.id;

  void select(String id) {
    if (!ref.read(profileCatalogProvider).any((profile) => profile.id == id)) {
      throw ArgumentError.value(id, 'id', 'Unknown profile');
    }
    state = id;
  }
}

final activeProfileProvider = Provider<PreviewProfile>((ref) {
  final id = ref.watch(activeProfileIdProvider);
  return ref
      .watch(profileCatalogProvider)
      .firstWhere((profile) => profile.id == id);
});

class AppNotice {
  const AppNotice({
    required this.id,
    required this.title,
    required this.message,
    this.isRead = false,
  });
  final String id;
  final String title;
  final String message;
  final bool isRead;

  AppNotice read() =>
      AppNotice(id: id, title: title, message: message, isRead: true);
}

final notificationFeedProvider =
    NotifierProvider<NotificationController, List<AppNotice>>(
      NotificationController.new,
    );

class NotificationController extends Notifier<List<AppNotice>> {
  @override
  List<AppNotice> build() => const [
    AppNotice(
      id: 'welcome',
      title: 'Chào mừng đến với MedicApp',
      message: 'Xem các hồ sơ gia đình tại mục Hồ sơ và tìm hướng dẫn tại mục Trợ giúp.',
    ),
    AppNotice(
      id: 'readability',
      title: 'Đọc dễ dàng hơn',
      message:
          'Bạn có thể tăng cỡ chữ trong phần cài đặt hiển thị của điện thoại.',
    ),
  ];

  void markRead(String id) {
    if (!state.any((notice) => notice.id == id && !notice.isRead)) return;
    state = List.unmodifiable([
      for (final notice in state)
        if (notice.id == id) notice.read() else notice,
    ]);
  }

  void markAllRead() {
    if (state.every((notice) => notice.isRead)) return;
    state = List.unmodifiable(state.map((notice) => notice.read()));
  }
}

final unreadCountProvider = Provider<int>(
  (ref) => ref
      .watch(notificationFeedProvider)
      .where((notice) => !notice.isRead)
      .length,
);
