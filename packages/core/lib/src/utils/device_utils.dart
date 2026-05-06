import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class DeviceUtils {
  static Future<String> getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    
    if (kIsWeb) {
      final webInfo = await deviceInfo.webBrowserInfo;
      return "${webInfo.vendor}_${webInfo.userAgent}_${webInfo.hardwareConcurrency}";
    }
    
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id; // Unique ID on Android
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown_ios';
    }
    
    return 'unknown_device';
  }

  /// Nettoie et lance un appel téléphonique avec le préfixe +221
  static Future<void> launchPhoneCall(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    
    // Garder uniquement les chiffres
    String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    
    // Si c'est juste "221", on considère que c'est vide
    if (cleanPhone == '221') return;

    // Si ça commence déjà par 221, on extrait le reste
    if (cleanPhone.startsWith('221') && cleanPhone.length > 3) {
      cleanPhone = cleanPhone.substring(3);
    }
    
    // Un numéro sénégalais valide (hors indicatif) fait 9 chiffres
    // Si on a moins, c'est probablement une erreur de saisie
    if (cleanPhone.length < 7) return; 

    final Uri url = Uri.parse('tel:+221$cleanPhone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  /// Nettoie et lance une conversation WhatsApp
  static Future<void> launchWhatsApp(String? phone, {String message = ""}) async {
    if (phone == null || phone.trim().isEmpty) return;
    
    String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone == '221') return;

    if (cleanPhone.startsWith('221') && cleanPhone.length > 3) {
      cleanPhone = cleanPhone.substring(3);
    }
    
    if (cleanPhone.length < 7) return;

    final String urlStr = 'https://wa.me/221$cleanPhone?text=${Uri.encodeComponent(message)}';
    final Uri url = Uri.parse(urlStr);
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
