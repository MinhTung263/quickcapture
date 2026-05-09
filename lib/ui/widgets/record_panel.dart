import 'package:flutter/material.dart';
import '../../core/app_constants.dart';

class RecordButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onTap;

  const RecordButton({
    super.key,
    required this.isRecording,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: isRecording ? 1.2 : 1.0),
        duration: const Duration(seconds: 1),
        builder: (context, scale, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              if (isRecording)
                Container(
                  width: 85 * scale,
                  height: 85 * scale,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppConstants.primaryColor.withOpacity(
                      0.15 - ((scale - 1) * 0.5),
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutBack,
                width: 80,
                height: 80,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isRecording
                        ? Colors.grey.shade300
                        : AppConstants.primaryColor.withOpacity(0.3),
                    width: 3.5,
                  ),
                  color: Colors.white,
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    width: isRecording ? 32 : 62,
                    height: isRecording ? 32 : 62,
                    decoration: BoxDecoration(
                      color: isRecording
                          ? const Color(0xFF3A3A3C)
                          : AppConstants.primaryColor,
                      borderRadius: BorderRadius.circular(isRecording ? 8 : 40),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
