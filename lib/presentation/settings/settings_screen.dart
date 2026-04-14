import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers/auth_provider.dart';
import '../../domain/providers/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        backgroundColor: auth?.role == 'driver' ? Colors.black87 : Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSettingsSection(
            'Préférences de l\'App',
            [
              _buildSettingsTile(context, ref, Icons.notifications_outlined, 'Notifications', true),
              _buildSettingsTile(context, ref, Icons.dark_mode_outlined, 'Mode Sombre', false),
              _buildSettingsTile(context, ref, Icons.language_outlined, 'Langue (Français)', null),
            ],
          ),
          const SizedBox(height: 20),
          _buildSettingsSection(
            'Compte & Sécurité',
            [
              _buildSettingsTile(context, ref, Icons.lock_outline, 'Changer le mot de passe', null),
              _buildSettingsTile(context, ref, Icons.security_outlined, 'Vérification en 2 étapes', false),
              _buildSettingsTile(context, ref, Icons.delete_outline, 'Supprimer mon compte', null, color: Colors.red),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 10, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingsTile(BuildContext context, WidgetRef ref, IconData icon, String title, bool? value, {Color? color}) {
    final isDarkMode = ref.watch(themeProvider) == ThemeMode.dark;
    
    return ListTile(
      leading: Icon(icon, color: color ?? (isDarkMode ? Colors.white70 : Colors.black87)),
      title: Text(title, style: TextStyle(color: color ?? (isDarkMode ? Colors.white : Colors.black87), fontWeight: FontWeight.w500)),
      trailing: value != null 
        ? Switch(
            value: title == 'Mode Sombre' ? isDarkMode : value, 
            onChanged: (val) {
              if (title == 'Mode Sombre') {
                ref.read(themeProvider.notifier).state = val ? ThemeMode.dark : ThemeMode.light;
              }
            }, 
            activeThumbColor: Colors.orange
          )
        : const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
        if (title == 'Supprimer mon compte') {
          _showDeleteConfirmation(context, ref);
        }
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer le compte ?"),
        content: const Text("Cette action est irréversible. Toutes vos données seront définitivement supprimées."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ANNULER")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(authProvider.notifier).deleteAccount();
                // AuthGate s'occupe de la redirection vers Login
              } catch (e) {
                if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString().replaceAll("Exception: ", "")), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("SUPPRIMER DÉFINITIVEMENT"),
          ),
        ],
      ),
    );
  }
}
