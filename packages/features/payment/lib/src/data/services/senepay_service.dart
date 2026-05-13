import 'dart:async';
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
      // Test de connexion basique d'abord
      debugPrint(">>> SenePayService: Test de connexion à Google...");
      try {
        await http.get(Uri.parse("https://www.google.com")).timeout(const Duration(seconds: 5));
        debugPrint(">>> SenePayService: Internet OK");
      } catch (e) {
        debugPrint(">>> SenePayService: Pas d'internet ou bloqué: $e");
      }

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

      debugPrint(">>> SenePayService: Appel $url (Timeout 60s)");
      
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "User-Agent": "Mozilla/5.0 (Linux; Android 10) TranSenApp/1.0"
        },
        body: jsonEncode(bodyMap),
      ).timeout(const Duration(seconds: 60));
      
      debugPrint(">>> SenePayService: Statut ${response.statusCode}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['checkoutUrl'] as String?;
      } else {
        throw Exception("Erreur Serveur: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint(">>> SenePayService Error: $e");
      if (e is TimeoutException) {
        throw Exception("Le serveur Render ne répond pas après 60s. Problème de réseau mobile ?");
      }
      rethrow;
    }
  }

  // ... autres méthodes ...
  Future<Map<String, dynamic>?> createPayout({
    required String externalId, required double amount, required String recipientPhone, required String recipientName, required String operator, String country = "SN", String? description, Map<String, dynamic>? metadata,
  }) async { return null; }
  Future<Map<String, dynamic>?> getPayoutStatus(String internalId) async { return null; }
  Future<Map<String, dynamic>?> checkCheckoutStatus(String orderReference) async { return null; }
}
