import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppConstants {
  static const channel = MethodChannel('quick_capture');

  // Colors
  static const primaryColor = Color(0xFFFF3B30); // Đỏ Apple
  static const secondaryColor = Color(0xFF007AFF); // Xanh iOS
  static const bgColor = Color(0xFFF2F2F7);

  // Styles
  static const borderRadius = 20.0;
  static const cardShadow = [
    BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
  ];
}
