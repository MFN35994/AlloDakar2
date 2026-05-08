import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionWidget extends StatelessWidget {
  final Color? color;
  final double fontSize;

  const AppVersionWidget({
    super.key,
    this.color,
    this.fontSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final version = snapshot.data!.version;
          final buildNumber = snapshot.data!.buildNumber;
          return Text(
            'v$version+$buildNumber',
            style: TextStyle(
              color: color ?? Colors.grey.withValues(alpha: 0.5),
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.0,
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
