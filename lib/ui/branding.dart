import 'package:flutter/material.dart';
import 'common.dart';

const appTitle = 'SRS AGENCIES';
const appTagline = 'Hardware & Building Materials';
const appSubtitle = 'Retail & Wholesale Billing Suite';

Widget srsLogoWidget({
  double size = 44,
  double radius = 12,
  bool showBorder = false,
  bool glass = false,
}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: glass ? Colors.white.withOpacity(0.1) : Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: showBorder ? lineColor : Colors.black.withOpacity(0.04),
        width: 0.5,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 15,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/images/srs_logo.jpg',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          color: const Color(0xFF1C1C1E), // Deep premium dark instead of bright red
          child: const Center(
            child: Text(
              'SRS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w400,
                fontFamily: 'NotoSans',
                fontSize: 14,
                letterSpacing: 2.0,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
