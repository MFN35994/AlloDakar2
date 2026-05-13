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
      
      final bodyMap = {
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
      };

      if (providerId != null && providerId.isNotEmpty) {
        bodyMap["providerId"] = providerId;
      }

      debugPrint(">>> SenePayService: Appel $url");
      
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(bodyMap),
      ).timeout(const Duration(seconds: 20));
      
      debugPrint(">>> SenePayService: Statut ${response.statusCode}");
      debugPrint(">>> SenePayService: Body ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data is Map && data.containsKey('checkoutUrl')) {
          return data['checkoutUrl'] as String?;
        }
        throw Exception("Réponse invalide de Render (pas de checkoutUrl)");
      } else {
        String error = "Erreur ${response.statusCode}";
        try {
          final errorData = jsonDecode(response.body);
          error = errorData['error'] ?? errorData['message'] ?? error;
        } catch (_) {}
        throw Exception(error);
      }
    } catch (e) {
      debugPrint(">>> SenePayService Error: $e");
      rethrow;
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
