import 'package:flutter/material.dart';
import 'common.dart';

const appTitle = 'SRS AGENCIES';
const appTagline = 'Hardware & Building Materials';
const appSubtitle = 'Retail & Wholesale Billing Suite';

Widget srsLogoWidget({
  double size = 44,
  double radius = 12,
  bool showBorder = true,
}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: showBorder ? Border.all(color: lineColor, width: 1.2) : null,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius - 1),
      child: Image.asset(
        'assets/images/srs_logo.jpg',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Container(
          color: const Color(0xFFC42B2B),
          child: const Center(
            child: Text(
              'SRS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
