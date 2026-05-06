import 'package:cloud_firestore/cloud_firestore.dart';

class PoolModel {
  final String id;
  final String departure;
  final String destination;
  final String status; // 'open', 'full', 'departed', 'completed'
  final List<String> passengerIds;
  final Map<String, dynamic> passengerDetails; // { uid: { 'name': '', 'phone': '', 'lat': 0.0, 'lng': 0.0 } }
  final String? driverId;
  final DateTime createdAt;
  final String scheduledDate;
  final int maxCapacity;
  final int currentFilling;

  PoolModel({
    required this.id,
    required this.departure,
    required this.destination,
    required this.status,
    required this.passengerIds,
    required this.passengerDetails,
    this.driverId,
    required this.createdAt,
    required this.scheduledDate,
    this.maxCapacity = 4,
    required this.currentFilling,
  });

  factory PoolModel.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return PoolModel(
      id: doc.id,
      departure: data['departure'] ?? '',
      destination: data['destination'] ?? '',
      status: data['status'] ?? 'open',
      passengerIds: List<String>.from(data['passengerIds'] ?? []),
      passengerDetails: data['passengerDetails'] ?? {},
      driverId: data['driverId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      scheduledDate: data['scheduledDate'] ?? '',
      maxCapacity: data['maxCapacity'] ?? 4,
      currentFilling: data['currentFilling'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'departure': departure,
      'destination': destination,
      'status': status,
      'passengerIds': passengerIds,
      'passengerDetails': passengerDetails,
      'driverId': driverId,
      'createdAt': Timestamp.fromDate(createdAt),
      'scheduledDate': scheduledDate,
      'maxCapacity': maxCapacity,
      'currentFilling': currentFilling,
    };
  }
}
