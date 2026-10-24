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
  });

  static const selfId = 'self';

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

  bool get isSelf => id == selfId;

  /// Short label for the switcher, e.g. "Myself" or "Parent · Mother / Senior Parent".
  String get relationshipLabel => isSelf || relationship == null
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
