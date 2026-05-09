// ============================================================================
// 🚀 MÀN HÌNH XEM VIDEO (FULLSCREEN PLAYER)
// ============================================================================
import 'dart:io';

import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    // Khởi tạo controller từ đường dẫn file cục bộ
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {});
        _controller.play(); // Tự động phát khi mở lên
        _hideControlsTimer(); // Tự động ẩn nút sau 3 giây
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
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) _hideControlsTimer();
  }

  @override
  void dispose() {
    _controller.dispose(); // Giải phóng bộ nhớ khi đóng màn hình
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Nền đen chuẩn điện ảnh
      body: SafeArea(
        child: GestureDetector(
          onTap: _toggleControls, // Chạm màn hình để bật/tắt menu
          child: Stack(
            children: [
              // 1. LỚP VIDEO HIỂN THỊ CHÍNH GIỮA
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
                  color: Colors.black.withOpacity(
                    0.4,
                  ), // Phủ mờ nhẹ để dễ nhìn nút
                  child: Stack(
                    children: [
                      // Nút Back và Tên Video ở trên cùng
                      Positioned(
                        top: 10,
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
                          ],
                        ),
                      ),

                      // Nút Play/Pause khổng lồ ở giữa
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _controller.value.isPlaying
                                  ? _controller.pause()
                                  : _controller.play();
                            });
                            _hideControlsTimer();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _controller.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 60,
                            ),
                          ),
                        ),
                      ),

                      // Thanh tiến trình (Timeline) ở dưới cùng
                      if (_controller.value.isInitialized)
                        Positioned(
                          bottom: 30,
                          left: 20,
                          right: 20,
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  ValueListenableBuilder(
                                    valueListenable: _controller,
                                    builder:
                                        (
                                          context,
                                          VideoPlayerValue value,
                                          child,
                                        ) {
                                          return Text(
                                            _formatDuration(value.position),
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          );
                                        },
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
                                allowScrubbing: true, // Cho phép kéo tua video
                                colors: const VideoProgressColors(
                                  playedColor: Color(
                                    0xFFFF3B30,
                                  ), // Màu đỏ Apple
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
      ),
    );
  }
}
