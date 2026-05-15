import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
      
      final returnUrl = kIsWeb ? "https://transen-pro.web.app/payment/success" : "$backendUrl/payment/success";
      final failUrl = kIsWeb ? "https://transen-pro.web.app/payment/cancel" : "$backendUrl/payment/cancel";

      final bodyMap = {
        "amount": amount.toInt(),
        "currency": "XOF",
        "orderReference": orderId,
        "description": description,
        "successUrl": returnUrl,
        "cancelUrl": failUrl,
        "webhookUrl": "$backendUrl/webhook/senepay",
        "metadata": {
          "order_id": orderId,
          "platform": kIsWeb ? "web_app" : "mobile_app"
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

  Future<Map<String, dynamic>?> createPayout({
    required double amount,
    required String recipientPhone,
    required String recipientName,
    required String operator,
    String? description,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Utilisateur non connecté");
      
      final idToken = await user.getIdToken();
      if (idToken == null) throw Exception("Impossible d'obtenir le jeton d'authentification");

      final url = Uri.parse("$backendUrl/api/payment/secure-payout");
      final bodyMap = {
        "amount": amount,
        "recipientPhone": recipientPhone,
        "recipientName": recipientName,
        "operator": operator,
        "description": description,
      };

      debugPrint(">>> SenePayService: Appel secure-payout vers $url");
      
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $idToken",
          "User-Agent": "Mozilla/5.0 (Linux; Android 10) TranSenApp/1.0"
        },
        body: jsonEncode(bodyMap),
      ).timeout(const Duration(seconds: 60));

      debugPrint(">>> SenePayService: Payout Statut ${response.statusCode}");
      debugPrint(">>> SenePayService: Payout Réponse ${response.body}");

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['error'] ?? "Erreur ${response.statusCode}");
      }
    } catch (e) {
      debugPrint(">>> SenePayService Payout Error: $e");
      if (e is TimeoutException) {
        throw Exception("Le serveur Render ne répond pas après 60s. Veuillez réessayer.");
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getPayoutStatus(String internalId) async { return null; }
  Future<Map<String, dynamic>?> checkCheckoutStatus(String orderReference) async { return null; }

  Future<void> recordCommission({
    required double amount,
    required String tripId,
    required String type,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final url = Uri.parse("$backendUrl/api/stats/record-commission");
      
      await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $idToken",
        },
        body: jsonEncode({
          "commission": amount,
          "tripId": tripId,
          "type": type,
        }),
      ).timeout(const Duration(seconds: 10));
      
      debugPrint(">>> Stats: Commission de $amount enregistrée via Backend");
    } catch (e) {
      debugPrint(">>> Stats Error: Impossible d'enregistrer la commission ($e)");
      // On ne bloque pas l'utilisateur si les stats échouent
    }
  }

  Future<void> processReferralReward(String referredUserId, String tripId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final url = Uri.parse("$backendUrl/api/admin/award-referral-reward");
      
      await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $idToken",
        },
        body: jsonEncode({
          "referredUserId": referredUserId,
          "tripId": tripId,
        }),
      ).timeout(const Duration(seconds: 10));
      
      debugPrint(">>> Parrainage: Demande de récompense envoyée au Backend");
    } catch (e) {
      debugPrint(">>> Parrainage Error: $e");
    }
  }
}
