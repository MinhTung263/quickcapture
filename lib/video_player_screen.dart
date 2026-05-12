// ============================================================================
// 🚀 MÀN HÌNH XEM VIDEO (FULLSCREEN PLAYER CÓ LƯU/XÓA)
// ============================================================================
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoPath;
  final String videoName;

  const VideoPlayerScreen({
    super.key,
    required this.videoPath,
    required this.videoName,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _showControls = true;
  static const channel = MethodChannel('quick_capture'); // Cầu nối Native

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _hideControlsTimer();
      });
  }

  void _hideControlsTimer() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _hideControlsTimer();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _seekRelative(int seconds) {
    if (!_controller.value.isInitialized) return;

    final currentPosition = _controller.value.position;
    final targetPosition = currentPosition + Duration(seconds: seconds);

    // Đảm bảo không tua quá thời lượng video hoặc nhỏ hơn 0
    if (targetPosition < Duration.zero) {
      _controller.seekTo(Duration.zero);
    } else if (targetPosition > _controller.value.duration) {
      _controller.seekTo(_controller.value.duration);
    } else {
      _controller.seekTo(targetPosition);
    }

    _hideControlsTimer(); // Reset bộ đếm ẩn menu
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: isError
            ? const Color(0xFFFF3B30)
            : const Color(0xFF34C759),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // 🚀 HÀM LƯU VIDEO
  Future<void> _saveVideo() async {
    if (_controller.value.isPlaying) _controller.pause(); // Tạm dừng phim

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF3B30)),
              ),
              SizedBox(width: 20),
              Text(
                "Đang lưu vào Ảnh...",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final result = await channel.invokeMethod("saveSpecificVideo", {
        "path": widget.videoPath,
      });
      if (mounted) Navigator.pop(context); // Đóng loading

      if (result == "Thành công") {
        _showSnackBar("Đã lưu vào Thư viện ảnh thành công!");
      } else {
        _showSnackBar(result, isError: true);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar("Lỗi: $e", isError: true);
    }
  }

  // 🚀 HÀM XÓA VIDEO
  Future<void> _deleteVideo() async {
    try {
      final bool success = await channel.invokeMethod("deleteVideo", {
        "path": widget.videoPath,
      });
      if (success) {
        if (mounted)
          Navigator.pop(
            context,
            'deleted',
          ); // Đóng player, báo về cho màn hình chính
      } else {
        _showSnackBar("Không thể xóa video", isError: true);
      }
    } catch (e) {
      _showSnackBar("Lỗi: $e", isError: true);
    }
  }

  void _confirmDelete() {
    if (_controller.value.isPlaying) _controller.pause(); // Tạm dừng phim

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Color(0xFFFF3B30),
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Xóa video này?",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              const Text(
                "Video sẽ bị xóa vĩnh viễn khỏi thiết bị.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Hủy",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Đóng popup xác nhận
                        _deleteVideo(); // Chạy hàm xóa
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3B30),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Xóa ngay",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        onVerticalDragUpdate: (details) {
          if (details.delta.dy > 10) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          children: [
            // 1. LỚP VIDEO
            Center(
              child: _controller.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const CircularProgressIndicator(color: Color(0xFFFF3B30)),
            ),
            

            // 2. LỚP ĐIỀU KHIỂN (CONTROLS OVERLAY)
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                color: Colors.black.withOpacity(0.4),
                child: Stack(
                  children: [
                    // Nút Back, Tên Video, Nút Lưu & Nút Xóa
                    Positioned(
                      top: topPadding + 10,
                      left: 10,
                      right: 10,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Text(
                              widget.videoName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 🚀 ICON LƯU
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(
                                0.15,
                              ), // Nền mờ sang trọng
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons
                                    .file_download_outlined, // Icon hiện đại hơn
                                color: Colors.white,
                                size: 24,
                              ),
                              onPressed: _saveVideo,
                              tooltip: "Lưu vào Ảnh",
                            ),
                          ),

                          // 🚀 NÚT XÓA (Thùng rác nét mảnh)
                          Container(
                            margin: const EdgeInsets.only(left: 6, right: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons
                                    .delete_outline_rounded, // Icon thùng rác nét mảnh
                                color: Colors.white,
                                size: 24,
                              ),
                              onPressed: _confirmDelete,
                              tooltip: "Xóa video",
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Nút Play/Pause ở giữa
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // ⏪ NÚT BACK 10S
                          _buildControlCircle(
                            icon: Icons.replay_10_rounded,
                            onTap: () => _seekRelative(-10),
                            size: 50,
                          ),

                          const SizedBox(width: 30),

                          // ▶️ NÚT PLAY/PAUSE (Nút chính)
                          _buildControlCircle(
                            icon: _controller.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            onTap: () {
                              setState(() {
                                _controller.value.isPlaying
                                    ? _controller.pause()
                                    : _controller.play();
                              });
                              _hideControlsTimer();
                            },
                            size: 70,
                            isMain: true,
                          ),

                          const SizedBox(width: 30),

                          // ⏩ NÚT FORWARD 10S
                          _buildControlCircle(
                            icon: Icons.forward_10_rounded,
                            onTap: () => _seekRelative(10),
                            size: 50,
                          ),
                        ],
                      ),
                    ),

                    // Thanh tiến trình (Timeline)
                    if (_controller.value.isInitialized)
                      Positioned(
                        bottom: bottomPadding + 30,
                        left: 20,
                        right: 20,
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                ValueListenableBuilder(
                                  valueListenable: _controller,
                                  builder:
                                      (
                                        context,
                                        VideoPlayerValue value,
                                        child,
                                      ) => Text(
                                        _formatDuration(value.position),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                ),
                                Text(
                                  _formatDuration(_controller.value.duration),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            VideoProgressIndicator(
                              _controller,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Color(0xFFFF3B30),
                                bufferedColor: Colors.white38,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Hàm bổ trợ vẽ các nút tròn mờ
Widget _buildControlCircle({
  required IconData icon,
  required VoidCallback onTap,
  required double size,
  bool isMain = false,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.all(isMain ? 16 : 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(isMain ? 0.2 : 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: size - 20),
    ),
  );
}
