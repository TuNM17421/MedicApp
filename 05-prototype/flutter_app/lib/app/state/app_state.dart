import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';

/// A person whose visits are managed in the app. Kept in memory, and on this
/// device only after the account holder agreed (see `health_consent.dart`).
class PreviewProfile {
  const PreviewProfile({
    required this.id,
    required this.name,
    required this.birthYear,
    required this.relationship,
    this.birthDate,
    this.gender,
    this.idNumber,
    this.address,
    this.conditions = const [],
  });
  final String id;
  final String name;
  final int birthYear;
  final String relationship;
  final DateTime? birthDate;
  final String? gender;

  /// CCCD number, only when the profile was created from a scanned card.
  final String? idNumber;
  final String? address;

  /// Ids from `visit_prep_catalog.dart` of conditions this person is followed
  /// for. Used only to personalise visit preparation notes.
  final List<String> conditions;

  PreviewProfile withConditions(List<String> value) => PreviewProfile(
    id: id,
    name: name,
    birthYear: birthYear,
    relationship: relationship,
    birthDate: birthDate,
    gender: gender,
    idNumber: idNumber,
    address: address,
    conditions: List.unmodifiable(value),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'birthYear': birthYear,
    'relationship': relationship,
    'birthDate': birthDate?.toIso8601String(),
    'gender': gender,
    'idNumber': idNumber,
    'address': address,
    'conditions': conditions,
  };

  factory PreviewProfile.fromJson(Map<String, Object?> json) => PreviewProfile(
    id: json['id']! as String,
    name: json['name']! as String,
    birthYear: json['birthYear']! as int,
    relationship: json['relationship']! as String,
    birthDate: switch (json['birthDate']) {
      final String value => DateTime.parse(value),
      _ => null,
    },
    gender: json['gender'] as String?,
    idNumber: json['idNumber'] as String?,
    address: json['address'] as String?,
    conditions: List.unmodifiable(
      (json['conditions'] as List<Object?>? ?? const []).cast<String>(),
    ),
  );
}

const demoProfiles = [
  PreviewProfile(
    id: 'self',
    name: 'Phạm Văn Hòa',
    birthYear: 1966,
    relationship: 'Bản thân',
    gender: 'Nam',
    conditions: ['diabetes', 'hypertension'],
  ),
  PreviewProfile(
    id: 'mother',
    name: 'Phạm Thị Lan',
    birthYear: 1948,
    relationship: 'Mẹ',
    gender: 'Nữ',
    conditions: ['gout', 'dyslipidemia'],
  ),
  PreviewProfile(
    id: 'child',
    name: 'Phạm Minh An',
    birthYear: 2017,
    relationship: 'Cháu',
  ),
];

final profileCatalogProvider =
    NotifierProvider<ProfileCatalogController, List<PreviewProfile>>(
      ProfileCatalogController.new,
    );

class ProfileCatalogController extends Notifier<List<PreviewProfile>> {
  /// The signed-in account's profiles. Signed out (only reachable in tests and
  /// the design preview, since the router sends users to sign-in) shows the
  /// demo family.
  @override
  List<PreviewProfile> build() {
    final phone = ref.watch(authSessionProvider);
    if (phone == null) return demoProfiles;
    return List.unmodifiable(
      ref.read(mockAccountStoreProvider)[phone]?.profiles ?? const [],
    );
  }

  void setConditions(String id, List<String> conditions) {
    state = List.unmodifiable([
      for (final profile in state)
        profile.id == id ? profile.withConditions(conditions) : profile,
    ]);
    ref.read(authSessionProvider.notifier).saveProfiles(state);
  }

  /// The account holder's own profile always stays first.
  void add(PreviewProfile profile) {
    if (state.any((value) => value.id == profile.id)) return;
    state = List.unmodifiable(
      profile.relationship == selfRelationship
          ? [profile, ...state]
          : [...state, profile],
    );
    ref.read(authSessionProvider.notifier).saveProfiles(state);
  }
}

const selfRelationship = 'Bản thân';

final activeProfileIdProvider =
    NotifierProvider<ActiveProfileController, String>(
      ActiveProfileController.new,
    );

class ActiveProfileController extends Notifier<String> {
  @override
  String build() {
    ref.watch(authSessionProvider);
    final profiles = ref.read(profileCatalogProvider);
    return profiles.isEmpty ? '' : profiles.first.id;
  }

  void select(String id) {
    if (!ref.read(profileCatalogProvider).any((profile) => profile.id == id)) {
      throw ArgumentError.value(id, 'id', 'Unknown profile');
    }
    state = id;
  }
}

final activeProfileProvider = Provider<PreviewProfile>((ref) {
  final id = ref.watch(activeProfileIdProvider);
  final profiles = ref.watch(profileCatalogProvider);
  return profiles.firstWhere(
    (profile) => profile.id == id,
    orElse: () => profiles.first,
  );
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
