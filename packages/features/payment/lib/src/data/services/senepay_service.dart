import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class SenePayService {
  static const String backendUrl = "https://transen-api.onrender.com";
  
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
    headers: {"Content-Type": "application/json"},
    // Optionnel: On peut désactiver la vérification SSL si vraiment on soupçonne un problème de certif sur Android
    // (Mais Let's Encrypt de Render devrait être ok)
  ));

  Future<String?> createCheckoutSession({
    required double amount,
    required String orderId,
    required String description,
    String? customerName,
    String? customerPhone,
    String? providerId,
  }) async {
    try {
      final url = "$backendUrl/api/payment/create-session";
      
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
          "platform": "mobile_app"
        },
        "expiresInMinutes": 60
      };

      if (providerId != null && providerId.isNotEmpty) {
        body["providerId"] = providerId;
      }
      
      debugPrint(">>> SenePayService: POST $url");
      debugPrint(">>> SenePayService: Body: $body");

      final response = await _dio.post(url, data: body);
      
      debugPrint(">>> SenePayService: Statut: ${response.statusCode}");
      debugPrint(">>> SenePayService: Data: ${response.data}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        return data['checkoutUrl'] as String?;
      } else {
        throw Exception("Code HTTP ${response.statusCode}");
      }
    } on DioException catch (e) {
      debugPrint(">>> SenePayService: DioException type=${e.type}");
      debugPrint(">>> SenePayService: DioException message=${e.message}");
      
      if (e.type == DioExceptionType.connectionTimeout) {
        throw Exception("Le serveur Render met trop de temps à répondre (Timeout).");
      }
      
      if (e.response?.data != null) {
        final errorMsg = e.response?.data['error'] ?? e.response?.data['message'] ?? "Erreur API";
        throw Exception(errorMsg);
      }
      
      throw Exception("Erreur de connexion : ${e.message}");
    } catch (e) {
      debugPrint(">>> SenePayService: Erreur inattendue: $e");
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
      final url = "$backendUrl/api/payment/create-payout";
      final response = await _dio.post(url, data: {
        "externalId": externalId,
        "amount": amount.toInt(),
        "recipientPhone": recipientPhone,
        "recipientName": recipientName,
        "country": country,
        "operator": operator,
        "description": description ?? "Retrait TranSen",
        "callbackUrl": "$backendUrl/webhook/payout",
        "metadata": metadata ?? {},
      });
      return response.data;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPayoutStatus(String internalId) async {
    try {
      final response = await _dio.get("$backendUrl/api/payment/payout-status/$internalId");
      return response.data;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> checkCheckoutStatus(String orderReference) async {
    try {
      final response = await _dio.get("$backendUrl/api/payment/check-status/$orderReference");
      return response.data;
    } catch (e) {
      return null;
    }
  }
}
