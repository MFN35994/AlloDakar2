import 'package:flutter/material.dart';

class SkeletonLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 15.0,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
