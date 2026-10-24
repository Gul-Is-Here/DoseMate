import 'package:cloud_firestore/cloud_firestore.dart';

enum VisitStatus { scheduled, cancelled }

/// One appointment of one profile, stored at
/// `users/{uid}/profiles/{profileId}/visits/{id}`.
class Visit {
  const Visit({
    required this.id,
    required this.title,
    required this.category,
    required this.startsAt,
    this.doctor = '',
    this.clinic = '',
    this.address = '',
    this.phone = '',
    this.notes = '',
    this.reminders = const [],
    this.departureAlerts = false,
    this.status = VisitStatus.scheduled,
    this.isPending = false,
    this.place,
  });

  factory Visit.fromMap(
    String id,
    Map<String, dynamic> data, {
    bool isPending = false,
  }) => Visit(
    id: id,
    title: data['title'] as String? ?? '',
    category: data['category'] as String? ?? '',
    startsAt:
        (data['startsAt'] as Timestamp?)?.toDate() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    doctor: data['doctor'] as String? ?? '',
    clinic: data['clinic'] as String? ?? '',
    address: data['address'] as String? ?? '',
    phone: data['phone'] as String? ?? '',
    notes: data['notes'] as String? ?? '',
    reminders: [
      for (final r in data['reminders'] as List? ?? const [])
        if (r is String) r,
    ],
    departureAlerts: data['departureAlerts'] as bool? ?? false,
    status:
        VisitStatus.values.asNameMap()[data['status']] ?? VisitStatus.scheduled,
    isPending: isPending,
    place: VisitPlace.fromMap(data),
  );

  final String id;
  final String title;
  final String category;

  /// Local date and time of the appointment.
  final DateTime startsAt;
  final String doctor;
  final String clinic;
  final String address;
  final String phone;
  final String notes;

  /// Reminder choices such as "1 day before".
  final List<String> reminders;
  final bool departureAlerts;
  final VisitStatus status;
  final bool isPending;

  /// The Google place picked for [address], if one was.
  final VisitPlace? place;

  /// "Dr. Robert Sterling • St. Jude Dental Clinic".
  String get who => [doctor, clinic].where((s) => s.isNotEmpty).join(' • ');

  Map<String, Object?> toWriteMap() => {
    'title': title,
    'category': category,
    'startsAt': Timestamp.fromDate(startsAt),
    'doctor': doctor,
    'clinic': clinic,
    'address': address,
    'phone': phone,
    'notes': notes,
    'reminders': reminders,
    'departureAlerts': departureAlerts,
    'status': status.name,
    ...VisitPlace.writeMap(place),
  };
}

/// A place chosen from address search. [Visit.address] holds its
/// formatted address.
class VisitPlace {
  const VisitPlace({
    required this.placeId,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String placeId;
  final String name;
  final double latitude;
  final double longitude;

  static VisitPlace? fromMap(Map<String, dynamic> data) {
    final id = data['placeId'], lat = data['latitude'], lng = data['longitude'];
    if (id is! String || lat is! num || lng is! num) return null;
    return VisitPlace(
      placeId: id,
      name: data['placeName'] as String? ?? '',
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
    );
  }

  /// Place fields for a merge write; removed when no place is chosen.
  static Map<String, Object> writeMap(VisitPlace? place) => {
    'placeId': place?.placeId ?? FieldValue.delete(),
    'placeName': place?.name ?? FieldValue.delete(),
    'latitude': place?.latitude ?? FieldValue.delete(),
    'longitude': place?.longitude ?? FieldValue.delete(),
  };
}
