import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class SenePayService {
  static const String backendUrl = "https://transen-api.onrender.com";
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {"Content-Type": "application/json"},
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
          "customer_name": customerName ?? "Client TranSen",
          "customer_phone": customerPhone ?? "",
          "platform": "mobile_app"
        },
        "expiresInMinutes": 60
      };

      if (providerId != null && providerId.isNotEmpty) {
        body["providerId"] = providerId;
      }
      
      debugPrint("Appel Proxy Render (Dio): $url");
      final response = await _dio.post(url, data: body);
      debugPrint("Réponse Proxy Render (Dio): ${response.statusCode}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        return data['checkoutUrl'] as String?;
      } else {
        String errorMsg = "Erreur ${response.statusCode}";
        if (response.data != null) {
          errorMsg = response.data['error'] ?? response.data['message'] ?? errorMsg;
        }
        throw Exception(errorMsg);
      }
    } on DioException catch (e) {
      debugPrint("Dio Error: ${e.type} - ${e.message}");
      String error = "Erreur réseau";
      if (e.response?.data != null) {
        error = e.response?.data['error'] ?? e.response?.data['message'] ?? error;
      }
      throw Exception(error);
    } catch (e) {
      debugPrint("SenePay Proxy Exception: $e");
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

      final response = await _dio.post(url, data: body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data;
      }
      return null;
    } catch (e) {
      debugPrint("SenePay Payout Proxy Exception: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPayoutStatus(String internalId) async {
    try {
      final url = "$backendUrl/api/payment/payout-status/$internalId";
      final response = await _dio.get(url);
      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> checkCheckoutStatus(String orderReference) async {
    try {
      final url = "$backendUrl/api/payment/check-status/$orderReference";
      final response = await _dio.get(url);
      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
