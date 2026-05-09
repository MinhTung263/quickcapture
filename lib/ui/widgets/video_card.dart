import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/app_constants.dart';
import '../../core/constants.dart';

class VideoCard extends StatelessWidget {
  final String path;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenuPressed;

  const VideoCard({
    super.key,
    required this.path,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuPressed,
  });

  String _getFileSize(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return "0 B";
      int bytes = file.lengthSync();
      const suffixes = ["B", "KB", "MB", "GB"];
      var i = (log(bytes) / log(1024)).floor();
      return ((bytes / pow(1024, i)).toStringAsFixed(1)) + ' ' + suffixes[i];
    } catch (_) => "0 B";
  }

  @override
  Widget build(BuildContext context) {
    final fileName = path.split('/').last.replaceAll(".mp4", "");
    return GestureDetector(
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          border: isSelected ? Border.all(color: AppConstants.primaryColor, width: 2) : null,
          boxShadow: AppConstants.cardShadow,
        ),
        child: ListTile(
          onTap: onTap,
          leading: isSelectionMode 
              ? Checkbox(value: isSelected, onChanged: (_) => onTap(), activeColor: AppConstants.primaryColor)
              : _buildIcon(),
          title: Text(fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text("MP4 • ${_getFileSize(path)}", style: const TextStyle(fontSize: 12)),
          trailing: isSelectionMode ? null : IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: onMenuPressed,
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 50, height: 50,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.redAccent, AppConstants.primaryColor]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
    );
  }
}