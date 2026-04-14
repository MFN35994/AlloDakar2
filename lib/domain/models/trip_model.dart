import 'package:cloud_firestore/cloud_firestore.dart';

class TripModel {
  final String id;
  final String departure;
  final String destination;
  final String type;
  final double price;
  final String status; // 'pending', 'accepted', 'completed'
  final DateTime createdAt;
  
  // Nouveaux champs Phase 11
  final int? seats;
  final String? scheduledDate;
  final String? baggageDescription;
  final String? clientName;
  final String? clientPhone;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final int? rating;
  final String? comment;

  TripModel({
    required this.id,
    required this.departure,
    required this.destination,
    required this.type,
    required this.price,
    required this.status,
    required this.createdAt,
    this.seats,
    this.scheduledDate,
    this.baggageDescription,
    this.clientName,
    this.clientPhone,
    this.driverId,
    this.driverName,
    this.driverPhone,
    this.rating,
    this.comment,
  });

  factory TripModel.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return TripModel(
      id: doc.id,
      departure: data['departure'] ?? '',
      destination: data['destination'] ?? '',
      type: data['type'] ?? 'Course',
      price: (data['price'] ?? 0).toDouble(),
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      seats: data['seats'],
      scheduledDate: data['scheduledDate'],
      baggageDescription: data['baggageDescription'],
      clientName: data['clientName'],
      clientPhone: data['clientPhone'],
      driverId: data['driverId'],
      driverName: data['driverName'],
      driverPhone: data['driverPhone'],
      rating: data['rating'],
      comment: data['comment'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'departure': departure,
      'destination': destination,
      'type': type,
      'price': price,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'seats': seats,
      'scheduledDate': scheduledDate,
      'baggageDescription': baggageDescription,
      'clientName': clientName,
      'clientPhone': clientPhone,
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'rating': rating,
      'comment': comment,
    };
  }
}

