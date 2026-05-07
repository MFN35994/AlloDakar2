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
    
    // 1. Enlever tout sauf les chiffres
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    
    // 2. Normalisation du préfixe Sénégal (221)
    // Tant qu'on a un 221 suivi de plus de 9 chiffres, on l'enlève
    while (digits.startsWith('221') && digits.length > 9) {
      digits = digits.substring(3);
    }
    
    // 3. Format standard Sénégal : 9 chiffres
    if (digits.length == 9) {
      final Uri url = Uri.parse('tel:+221$digits');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
      return;
    }

    // 4. Fallback pour numéros déjà préfixés ou internationaux
    if (digits.length >= 7) {
      final String prefix = phone.startsWith('+') ? '+' : '';
      final Uri url = Uri.parse('tel:$prefix$digits');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    }
  }

  /// Nettoie et lance une conversation WhatsApp
  static Future<void> launchWhatsApp(String? phone, {String message = ""}) async {
    if (phone == null || phone.trim().isEmpty) return;
    
    // 1. Enlever tout sauf les chiffres
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    
    // 2. Normalisation du préfixe
    while (digits.startsWith('221') && digits.length > 9) {
      digits = digits.substring(3);
    }
    
    // 3. Format final WhatsApp (préfixe numérique obligatoire)
    String finalPhone = digits;
    if (digits.length == 9) {
      finalPhone = '221$digits';
    } else if (digits.length > 9 && digits.startsWith('221')) {
      finalPhone = digits;
    } else if (digits.length < 9) {
      debugPrint("DeviceUtils: Numéro WhatsApp trop court: $digits");
      return;
    }

    final String urlStr = 'https://wa.me/$finalPhone?text=${Uri.encodeComponent(message)}';
    final Uri url = Uri.parse(urlStr);
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
