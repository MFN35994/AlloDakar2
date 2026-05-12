import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class SenePayService {
  static const String backendUrl = "https://transen-api.onrender.com";
  
  Future<String?> createCheckoutSession({
    required double amount,
    required String orderId,
    required String description,
    String? customerName,
    String? customerPhone,
    String? providerId,
  }) async {
    try {
      final url = Uri.parse("$backendUrl/api/payment/create-session");
      
      final body = jsonEncode({
        "amount": amount.toInt(),
        "currency": "XOF",
        "orderReference": orderId,
        "description": description,
        "successUrl": "https://transen-pro.web.app/payment/success",
        "cancelUrl": "https://transen-pro.web.app/payment/cancel",
        "webhookUrl": "$backendUrl/webhook/senepay",
        "metadata": {
          "order_id": orderId,
          "platform": "mobile_app"
        },
        "expiresInMinutes": 60
      });

      debugPrint(">>> SenePayService (HTTP): POST $url");
      
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: body,
      ).timeout(const Duration(seconds: 25));
      
      debugPrint(">>> SenePayService (HTTP): Statut: ${response.statusCode}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['checkoutUrl'] as String?;
      } else {
        final error = jsonDecode(response.body)['error'] ?? "Erreur ${response.statusCode}";
        throw Exception(error);
      }
    } catch (e) {
      debugPrint(">>> SenePayService (HTTP) Error: $e");
      // On propage l'erreur brute pour voir le message système
      throw Exception("Erreur connexion: $e");
    }
  }

  Future<Map<String, dynamic>?> createPayout({
    required String externalId,
    required double amount,
    required String recipientPhone,
    required String recipientName,
    required String operator,
    String country = "SN",
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final url = Uri.parse("$backendUrl/api/payment/create-payout");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "externalId": externalId,
          "amount": amount.toInt(),
          "recipientPhone": recipientPhone,
          "recipientName": recipientName,
          "country": country,
          "operator": operator,
          "description": description ?? "Retrait TranSen",
          "callbackUrl": "$backendUrl/webhook/payout",
          "metadata": metadata ?? {},
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPayoutStatus(String internalId) async {
    try {
      final response = await http.get(Uri.parse("$backendUrl/api/payment/payout-status/$internalId"));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> checkCheckoutStatus(String orderReference) async {
    try {
      final response = await http.get(Uri.parse("$backendUrl/api/payment/check-status/$orderReference"));
      if (response.statusCode == 200) return jsonDecode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }
}
