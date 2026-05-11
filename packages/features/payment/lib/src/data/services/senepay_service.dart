import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class SenePayService {
  // PLUS DE CLÉS ICI ! Sécurité maximale.
  // Vos clés sont maintenant dans les variables d'environnement de Render.
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
      
      final body = {
        "amount": amount.toInt(),
        "currency": "XOF",
        "orderReference": orderId,
        "description": description,
        "successUrl": "https://transen-pro.web.app/payment/success",
        "cancelUrl": "https://transen-pro.web.app/payment/cancel",
        "webhookUrl": "$backendUrl/webhook/senepay",
        "metadata": {
          "order_id": orderId,
          "customer_name": customerName ?? "Client TranSen",
          "customer_phone": customerPhone ?? "",
          "platform": "mobile_app"
        },
        "expiresInMinutes": 60
      };

      if (providerId != null && providerId.isNotEmpty) {
        body["providerId"] = providerId;
      }
      
      debugPrint("Appel Proxy Render: $url");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));
      debugPrint("Réponse Proxy Render: ${response.statusCode}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['checkoutUrl'] as String?;
      } else {
        String errorMsg = "Erreur ${response.statusCode}";
        try {
          final errorData = jsonDecode(response.body);
          errorMsg = errorData['error'] ?? errorData['message'] ?? errorMsg;
        } catch (_) {}
        debugPrint("SenePay Proxy Error: $errorMsg");
        // On pourrait lever une exception pour la catcher dans l'UI
        throw Exception(errorMsg);
      }
    } catch (e) {
      debugPrint("SenePay Proxy Exception: $e");
      rethrow; // Laisser l'UI gérer l'erreur
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
      final body = {
        "externalId": externalId,
        "amount": amount.toInt(),
        "recipientPhone": recipientPhone,
        "recipientName": recipientName,
        "country": country,
        "operator": operator,
        "description": description ?? "Retrait TranSen",
        "callbackUrl": "$backendUrl/webhook/payout",
        "metadata": metadata ?? {},
      };

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        debugPrint("SenePay Payout Proxy Error: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("SenePay Payout Proxy Exception: $e");
      return null;
    }
  }

  // Pour les statuts, nous pouvons continuer à appeler SenePay directement 
  // car ce sont des requêtes GET moins sensibles, MAIS par souci de cohérence
  // et pour cacher l'API Key, il vaudrait mieux les passer aussi par le proxy.
  // Pour l'instant, laissons-les ainsi ou passons les via le proxy si besoin.
  
  Future<Map<String, dynamic>?> getPayoutStatus(String internalId) async {
    try {
      final url = Uri.parse("$backendUrl/api/payment/payout-status/$internalId");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> checkCheckoutStatus(String orderReference) async {
    try {
      final url = Uri.parse("$backendUrl/api/payment/check-status/$orderReference");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
