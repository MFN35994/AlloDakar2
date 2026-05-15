import 'package:cloud_firestore/cloud_firestore.dart';

class TripModel {
  final String id;
  final String departure;
  final String destination;
  final String type;
  final double price;
  final String status; // 'pending', 'accepted', 'completed'
  final DateTime createdAt;
  
  final int? seats;
  final String? scheduledDate;
  final String? baggageDescription;
  final String? clientName;
  final String? clientPhone;
  final String? clientId;
  final String? senderPhone;
  final String? receiverPhone;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final int? rating;
  final String? comment;
  final String? paymentMethod;
  final Map<String, dynamic>? passengerDetails;
  final double? destinationLat;
  final double? destinationLng;
  final double? pointsDiscount;

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
    this.clientId,
    this.senderPhone,
    this.receiverPhone,
    this.driverId,
    this.driverName,
    this.driverPhone,
    this.rating,
    this.comment,
    this.paymentMethod,
    this.passengerDetails,
    this.destinationLat,
    this.destinationLng,
    this.pointsDiscount,
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
      clientId: data['clientId'],
      senderPhone: data['senderPhone'],
      receiverPhone: data['receiverPhone'],
      driverId: data['driverId'],
      driverName: data['driverName'],
      driverPhone: data['driverPhone'],
      rating: data['rating'],
      comment: data['comment'],
      paymentMethod: data['paymentMethod'],
      passengerDetails: data['passengerDetails'],
      destinationLat: data['destinationLat']?.toDouble(),
      destinationLng: data['destinationLng']?.toDouble(),
      pointsDiscount: data['pointsDiscount']?.toDouble(),
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
      'clientId': clientId,
      'senderPhone': senderPhone,
      'receiverPhone': receiverPhone,
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'rating': rating,
      'comment': comment,
      'paymentMethod': paymentMethod,
      'passengerDetails': passengerDetails,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
      'pointsDiscount': pointsDiscount,
    };
  }
}
