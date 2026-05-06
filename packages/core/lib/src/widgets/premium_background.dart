import 'dart:ui';
import 'package:flutter/material.dart';

class PremiumBackground extends StatelessWidget {
  final Widget child;
  final List<Color>? blobColors;

  const PremiumBackground({
    super.key,
    required this.child,
    this.blobColors,
  });

  @override
  Widget build(BuildContext context) {
    final colors = blobColors ?? [
      const Color(0xFF2ECC71).withValues(alpha: 0.3),
      const Color(0xFF27AE60).withValues(alpha: 0.2),
      const Color(0xFFF1C40F).withValues(alpha: 0.1),
    ];

    return Stack(
      children: [
        // Background Blobs
        Positioned(
          top: -100,
          right: -50,
          child: _Blob(color: colors[0], size: 300),
        ),
        Positioned(
          bottom: -50,
          left: -100,
          child: _Blob(color: colors[1], size: 400),
        ),
        if (colors.length > 2)
          Positioned(
            top: 200,
            left: -50,
            child: _Blob(color: colors[2], size: 200),
          ),
        
        // Blur Layer
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
        
        // Content
        child,
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;

  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}
