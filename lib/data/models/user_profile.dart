import 'package:cloud_firestore/cloud_firestore.dart';

/// The sign-up / setup choice: the account holder, or someone they care for.
enum AccountFor { myself, caregiver }

/// Who a managed profile represents. Only the account holder is [self].
enum ProfileType {
  self('Myself'),
  parent('Parent'),
  spouse('Spouse'),
  other('Other');

  const ProfileType(this.label);

  final String label;

  AccountFor get accountFor =>
      this == self ? AccountFor.myself : AccountFor.caregiver;

  /// Maps the existing relationship choices onto a profile type.
  static ProfileType fromRelationship(String? relationship) =>
      switch (relationship) {
        'Mother / Senior Parent' || 'Father / Senior Parent' => parent,
        'Spouse or Partner' => spouse,
        _ => other,
      };

  /// The relationship preselected when adding a profile of this type.
  String get defaultRelationship => switch (this) {
    parent => 'Mother / Senior Parent',
    spouse => 'Spouse or Partner',
    _ => 'Home Care Client',
  };
}

/// What a caregiver may do with a profile shared with them, as chosen by
/// the owner. Enforced by Firestore rules and Cloud Functions.
class CarePermissions {
  const CarePermissions({
    this.checklist = false,
    this.alerts = false,
    this.appointments = false,
  });

  factory CarePermissions.fromMap(Object? data) {
    final m = data is Map ? data : const {};
    return CarePermissions(
      checklist: m['checklist'] == true,
      alerts: m['alerts'] == true,
      appointments: m['appointments'] == true,
    );
  }

  /// "View daily dose checklist": medicine names, times and taken/skipped,
  /// without dosage, notes or photos.
  final bool checklist;

  /// "Missed dose alert escalation". Saved; alerts are not delivered yet.
  final bool alerts;

  /// "Manage appointment schedule": read, add and reschedule visits.
  final bool appointments;

  bool get any => checklist || alerts || appointments;

  Map<String, bool> toMap() => {
    'checklist': checklist,
    'alerts': alerts,
    'appointments': appointments,
  };

  CarePermissions copyWith({
    bool? checklist,
    bool? alerts,
    bool? appointments,
  }) => CarePermissions(
    checklist: checklist ?? this.checklist,
    alerts: alerts ?? this.alerts,
    appointments: appointments ?? this.appointments,
  );

  @override
  bool operator ==(Object other) =>
      other is CarePermissions &&
      other.checklist == checklist &&
      other.alerts == alerts &&
      other.appointments == appointments;

  @override
  int get hashCode => Object.hash(checklist, alerts, appointments);
}

/// Access to a profile another account owns, from
/// `users/{uid}/sharedProfiles/{ownerUid}_{profileId}`.
class SharedAccess {
  const SharedAccess({
    required this.ownerUid,
    required this.profileId,
    required this.ownerName,
    required this.permissions,
  });

  final String ownerUid;

  /// The profile's id in the owner's account.
  final String profileId;
  final String ownerName;
  final CarePermissions permissions;
}

/// One managed profile, stored at `users/{uid}/profiles/{id}`. The account
/// holder's profile always has the id [selfId].
class UserProfile {
  const UserProfile({
    required this.id,
    required this.type,
    required this.fullName,
    this.relationship,
    this.dateOfBirth,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.photoUrl,
    this.photoPath,
    this.share,
  });

  static const selfId = 'self';

  /// A profile shared with this account. Its local [id] is
  /// `sh_{ownerUid}_{profileId}`; it is never written back as a profile.
  factory UserProfile.shared(Map<String, dynamic> data) {
    final ownerUid = data['ownerUid'] as String? ?? '';
    final profileId = data['profileId'] as String? ?? '';
    return UserProfile(
      id: sharedIdFor(ownerUid, profileId),
      type: ProfileType.other,
      fullName: data['profileName'] as String? ?? '',
      share: SharedAccess(
        ownerUid: ownerUid,
        profileId: profileId,
        ownerName: data['ownerName'] as String? ?? '',
        permissions: CarePermissions.fromMap(data['permissions']),
      ),
    );
  }

  static String sharedIdFor(String ownerUid, String profileId) =>
      'sh_${ownerUid}_$profileId';

  factory UserProfile.fromMap(String id, Map<String, dynamic> data) =>
      UserProfile(
        id: id,
        type:
            ProfileType.values.asNameMap()[data['type']] ??
            (id == selfId ? ProfileType.self : ProfileType.other),
        fullName: data['fullName'] as String? ?? '',
        relationship: data['relationship'] as String?,
        dateOfBirth: (data['dateOfBirth'] as Timestamp?)?.toDate(),
        emergencyContactName: data['emergencyContactName'] as String?,
        emergencyContactPhone: data['emergencyContactPhone'] as String?,
        photoUrl: data['photoUrl'] as String?,
        photoPath: data['photoPath'] as String?,
      );

  final String id;
  final ProfileType type;
  final String fullName;

  /// Only set for profiles other than the account holder.
  final String? relationship;
  final DateTime? dateOfBirth;
  final String? emergencyContactName;
  final String? emergencyContactPhone;

  /// Download URL and Storage path of the uploaded photo.
  final String? photoUrl;
  final String? photoPath;

  /// Set when another account owns this profile and shared it.
  final SharedAccess? share;

  bool get isSelf => id == selfId;

  bool get isShared => share != null;

  /// Short label for the switcher, e.g. "Myself" or "Parent · Mother / Senior Parent".
  String get relationshipLabel => isShared
      ? 'Shared by ${share!.ownerName}'
      : isSelf || relationship == null
      ? type.label
      : '${type.label} · $relationship';

  UserProfile copyWith({String? id, String? photoUrl, String? photoPath}) =>
      UserProfile(
        id: id ?? this.id,
        type: type,
        fullName: fullName,
        relationship: relationship,
        dateOfBirth: dateOfBirth,
        emergencyContactName: emergencyContactName,
        emergencyContactPhone: emergencyContactPhone,
        photoUrl: photoUrl ?? this.photoUrl,
        photoPath: photoPath ?? this.photoPath,
        share: share,
      );

  /// The user-editable fields to write with a merge; empty optional fields
  /// are removed so stale values never linger. Photo fields are only written
  /// when set, and bookkeeping fields (createdAt, etc.) are never touched.
  Map<String, Object> toWriteMap() {
    Object orDelete(Object? value) => value ?? FieldValue.delete();
    return {
      'type': type.name,
      'fullName': fullName,
      'relationship': orDelete(isSelf ? null : relationship),
      'dateOfBirth': orDelete(
        dateOfBirth == null ? null : Timestamp.fromDate(dateOfBirth!),
      ),
      'emergencyContactName': orDelete(emergencyContactName),
      'emergencyContactPhone': orDelete(emergencyContactPhone),
      'photoUrl': ?photoUrl,
      'photoPath': ?photoPath,
    };
  }
}

/// Account-wide state shared by all profiles, stored at `users/{uid}`.
class AccountState {
  const AccountState({this.setupCompleted = false, this.activeProfileId});

  factory AccountState.fromMap(Map<String, dynamic>? data) => AccountState(
    // `profileCompleted` is the pre-migration name of the same flag.
    setupCompleted:
        (data?['setupCompleted'] ?? data?['profileCompleted']) as bool? ??
        false,
    activeProfileId: data?['activeProfileId'] as String?,
  );

  /// Profile Setup has been saved at least once; skipping leaves it false.
  final bool setupCompleted;
  final String? activeProfileId;
}
