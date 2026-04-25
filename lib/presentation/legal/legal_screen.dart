import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../core/theme/transen_colors.dart';

class LegalScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const LegalScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  String _content = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    final text = await rootBundle.loadString(widget.assetPath);
    if (mounted) {
      setState(() {
        _content = text;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: TranSenColors.darkGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: TranSenColors.primaryGreen))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final lines = _content.split('\n');
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index].trim();
        if (line.isEmpty) return const SizedBox(height: 8);

        // Titre principal H1
        if (line.startsWith('# ')) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 20, top: 10),
            child: Text(
              line.substring(2),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: TranSenColors.darkGreen,
              ),
            ),
          );
        }

        // Sous-titres H2
        if (line.startsWith('## ')) {
          return Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 8),
            child: Text(
              line.substring(3),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: TranSenColors.primaryGreen,
              ),
            ),
          );
        }

        // Sous-sous-titres H3
        if (line.startsWith('### ')) {
          return Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              line.substring(4),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          );
        }

        // Points de liste
        if (line.startsWith('- ')) {
          final content = line.substring(2).replaceAllMapped(
            RegExp(r'\*\*(.+?)\*\*'),
            (m) => m.group(1)!,
          );
          return Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 6, color: TranSenColors.primaryGreen),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildRichText(content),
                ),
              ],
            ),
          );
        }

        // Texte normal
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _buildRichText(line.replaceAllMapped(
            RegExp(r'\*\*(.+?)\*\*'),
            (m) => m.group(1)!,
          )),
        );
      },
    );
  }

  Widget _buildRichText(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        color: Colors.black87,
        height: 1.6,
      ),
    );
  }
}
