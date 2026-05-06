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
    if (phone == null || phone.isEmpty) return;
    
    // Garder uniquement les chiffres
    String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    
    // Si ça commence déjà par 221, on enlève pour harmoniser
    if (cleanPhone.startsWith('221')) {
      cleanPhone = cleanPhone.substring(3);
    }
    
    // On force le +221
    final Uri url = Uri.parse('tel:+221$cleanPhone');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  /// Nettoie et lance une conversation WhatsApp
  static Future<void> launchWhatsApp(String? phone, {String message = ""}) async {
    if (phone == null || phone.isEmpty) return;
    
    String cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.startsWith('221')) {
      cleanPhone = cleanPhone.substring(3);
    }
    
    final String urlStr = 'https://wa.me/221$cleanPhone?text=${Uri.encodeComponent(message)}';
    final Uri url = Uri.parse(urlStr);
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
