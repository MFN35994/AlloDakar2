import 'package:flutter/material.dart';

class PoolProgressIndicator extends StatelessWidget {
  final int current;
  final int total;
  final String? estimatedDeparture;

  const PoolProgressIndicator({
    super.key,
    required this.current,
    this.total = 4,
    this.estimatedDeparture,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Remplissage du trajet',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
            Text(
              '$current / $total',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.deepOrange,
                fontSize: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: current / total,
            backgroundColor: Colors.grey.shade200,
            color: Colors.deepOrange,
            minHeight: 12,
          ),
        ),
        if (estimatedDeparture != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16, color: Colors.blueGrey),
              const SizedBox(width: 4),
              Text(
                estimatedDeparture!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.blueGrey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
