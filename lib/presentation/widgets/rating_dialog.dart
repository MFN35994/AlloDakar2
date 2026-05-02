import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/transen_colors.dart';
import '../../data/repositories/trip_repository.dart';
import '../../domain/providers/auth_provider.dart';

class RatingDialog extends StatefulWidget {
  final String tripId;
  final String? driverId;

  const RatingDialog({super.key, required this.tripId, this.driverId});

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _rating = 0;
  final _commentController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Si pas de chauffeur connu, on propose juste de fermer
    final hasDriver = widget.driverId != null && widget.driverId!.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header avec bouton fermer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 32),
                const Icon(Icons.star_rate_rounded, color: Colors.amber, size: 36),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasDriver
                  ? 'Comment s\'est passée votre course ? 🚕'
                  : 'Course terminée !',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              hasDriver
                  ? 'Votre avis aide à améliorer la qualité de TranSen.'
                  : 'Merci d\'avoir utilisé TranSen.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 25),

            if (hasDriver) ...[
              // Étoiles
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  return GestureDetector(
                    onTap: () => setState(() => _rating = index + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        index < _rating ? Icons.star_rounded : Icons.star_border_rounded,
                        color: index < _rating ? Colors.amber : Colors.grey.shade300,
                        size: 44,
                      ),
                    ),
                  );
                }),
              ),

              // Label texte selon la note
              if (_rating > 0) ...[
                const SizedBox(height: 8),
                Text(
                  ['', 'Très mauvais 😤', 'Mauvais 😕', 'Moyen 😐', 'Bien 😊', 'Excellent ! 🤩'][_rating],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: [Colors.transparent, Colors.red, Colors.orange, Colors.amber, Colors.lightGreen, TranSenColors.primaryGreen][_rating],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Commentaire
              TextField(
                controller: _commentController,
                decoration: InputDecoration(
                  hintText: 'Laissez un petit mot (optionnel)',
                  hintStyle: const TextStyle(fontSize: 13),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 18),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),

              // Bouton envoyer
              Consumer(builder: (context, ref, child) {
                final auth = ref.watch(authProvider);
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_rating == 0 || _isLoading || auth == null)
                        ? null
                        : () async {
                            setState(() => _isLoading = true);
                            try {
                              await ref.read(tripRepositoryProvider).submitRating(
                                tripId: widget.tripId,
                                driverId: widget.driverId!,
                                userId: auth.userId,
                                userName: auth.name ?? 'Client',
                                rating: _rating,
                                comment: _commentController.text.trim(),
                              );
                              if (context.mounted) Navigator.pop(context);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Erreur: ${e.toString()}"),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _isLoading = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TranSenColors.primaryGreen,
                      disabledBackgroundColor: Colors.grey.shade200,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('ENVOYER MON AVIS', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                );
              }),

              // Bouton passer
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Passer', style: TextStyle(color: Colors.grey)),
              ),
            ] else ...[
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: TranSenColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: const Text('RETOUR À L\'ACCUEIL', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
