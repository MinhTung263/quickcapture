import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'video_player_screen.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const QuickCaptureApp());
}

class QuickCaptureApp extends StatelessWidget {
  const QuickCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quick Capture',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFFF3B30), // Đỏ chuẩn Apple
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF2F2F7), // Nền xám nhạt iOS
        fontFamily: 'Roboto', // Sử dụng font mặc định mượt mà
      ),
      home: const ScreenRecordApp(),
    );
  }
}

class ScreenRecordApp extends StatefulWidget {
  const ScreenRecordApp({super.key});
  @override
  State<ScreenRecordApp> createState() => _ScreenRecordAppState();
}

class _ScreenRecordAppState extends State<ScreenRecordApp>
    with WidgetsBindingObserver {
  static const channel = MethodChannel('quick_capture');
  String status = "Sẵn sàng";
  List<String> videoPaths = [];
  bool isLoading = false;
  bool isRecording = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupNativeListener();
    loadVideoList();
  }

  void _setupNativeListener() {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "onVideoSaved":
          if (mounted) {
            setState(() {
              isRecording = false;
              status = "Đã lưu video! Đang làm mới...";
            });
            await loadVideoList();
          }
          break;
        case "onRecordingStarted":
          if (mounted) {
            setState(() {
              isRecording = true;
              status = "Đang ghi hình...";
            });
          }
          break;
        case "onRecordingStopped":
          if (mounted) {
            setState(() {
              isRecording = false;
              status = "Sẵn sàng";
            });
          }
          break;
        default:
          debugPrint("Chưa xử lý tín hiệu từ Native: ${call.method}");
          break;
      }
      return null;
    });
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> startRecord() async {
    try {
      final result = await channel.invokeMethod("startRecord");
      if (mounted) setState(() => status = result);
    } catch (e) {
      _showSnackBar("Lỗi: $e", isError: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final bool hasNew = await channel.invokeMethod("checkNewVideoStatus");
      if (hasNew) {
        if (mounted) setState(() => isRecording = false);
        loadVideoList();
      } else {
        final bool recording = await channel.invokeMethod("isRecording");
        if (mounted) {
          setState(() {
            isRecording = recording;
            if (isRecording) {
              status = "Đang ghi hình...";
            } else {
              if (status == "Hãy chọn 'Bắt đầu truyền phát'..." ||
                  status.contains("Vui lòng cấp quyền")) {
                status = "Sẵn sàng";
              }
            }
          });
        }
      }
    }
  }

  Future<void> loadVideoList() async {
    if (isLoading) return;
    setState(() {
      isLoading = true;
      if (!status.contains("Đã lưu")) status = "Đang quét...";
    });

    await Future.delayed(const Duration(milliseconds: 800));

    try {
      final List<dynamic>? paths = await channel.invokeMethod("getVideoList");
      if (mounted) {
        setState(() {
          videoPaths = paths?.cast<String>() ?? [];
          status = videoPaths.isEmpty ? "Sẵn sàng" : "Đã tải danh sách";
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> saveVideoToPhotos(String path) async {
    _showLoadingDialog("Đang lưu vào Ảnh...");
    try {
      final result = await channel.invokeMethod("saveSpecificVideo", {
        "path": path,
      });
      if (mounted) Navigator.pop(context);

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

  Future<void> stopRecord() async {
    try {
      final result = await channel.invokeMethod("stopRecord");
      if (result == "IOS_FORCE_STOPPING") {
        if (mounted) setState(() => status = "Đang chờ iOS đóng gói video...");
      } else {
        if (mounted) setState(() => status = "Đang dừng và đóng gói video...");
      }
    } catch (e) {
      _showSnackBar("Lỗi: $e", isError: true);
    }
  }

  Future<void> deleteVideo(String path) async {
    try {
      final bool success = await channel.invokeMethod("deleteVideo", {
        "path": path,
      });
      if (success) {
        _showSnackBar("Đã xóa video khỏi thiết bị");
        loadVideoList();
      }
    } catch (e) {
      _showSnackBar("Lỗi: $e", isError: true);
    }
  }

  String _getFileSize(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return "Không xác định";
      int bytes = file.lengthSync();
      if (bytes <= 0) return "0 B";
      const suffixes = ["B", "KB", "MB", "GB", "TB"];
      var i = (log(bytes) / log(1024)).floor();
      return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
    } catch (e) {
      return "Lỗi đọc file";
    }
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

  void _showLoadingDialog(String text) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF3B30)),
              ),
              const SizedBox(width: 20),
              Text(
                text,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_rounded, color: Color(0xFFFF3B30), size: 24),
            SizedBox(width: 8),
            Text(
              "Quick Capture",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent, // Ngăn chặn đổi màu khi cuộn
        actions: [
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.black87),
              onPressed: loadVideoList,
              tooltip: 'Làm mới',
            ),
        ],
      ),
      body: Column(
        children: [
          _buildRecordPanel(),
          _buildListHeader(),
          Expanded(
            child: videoPaths.isEmpty ? _buildEmptyState() : _buildVideoList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 20, bottom: 35),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildStatusBadge(),
          const SizedBox(height: 35),

          GestureDetector(
            onTap: isRecording ? stopRecord : startRecord,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 1.0, end: isRecording ? 1.2 : 1.0),
              duration: const Duration(seconds: 1),
              curve: Curves.easeInOutSine,
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
                          color: const Color(
                            0xFFFF3B30,
                          ).withOpacity(0.15 - ((scale - 1) * 0.5)),
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
                              : const Color(0xFFFF3B30).withOpacity(0.3),
                          width: 3.5,
                        ),
                        color: Colors.white,
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutBack,
                          width: isRecording ? 32 : 62,
                          height: isRecording ? 32 : 62,
                          decoration: BoxDecoration(
                            color: isRecording
                                ? const Color(0xFF3A3A3C)
                                : const Color(0xFFFF3B30),
                            borderRadius: BorderRadius.circular(
                              isRecording ? 8 : 40,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (isRecording
                                            ? Colors.black
                                            : const Color(0xFFFF3B30))
                                        .withOpacity(isRecording ? 0.2 : 0.4),
                                blurRadius: 15,
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
              onEnd: () {
                if (isRecording && mounted) setState(() {});
              },
            ),
          ),

          const SizedBox(height: 20),
          Text(
            isRecording ? "CHẠM ĐỂ DỪNG" : "CHẠM ĐỂ QUAY",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 1.2,
              color: isRecording ? Colors.grey[600] : const Color(0xFFFF3B30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color badgeColor = isRecording
        ? const Color(0xFFFF3B30)
        : (isLoading ? Colors.orange : const Color(0xFF007AFF));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: badgeColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRecording)
            const Icon(
              Icons.fiber_manual_record,
              size: 14,
              color: Color(0xFFFF3B30),
            )
          else if (isLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
              ),
            )
          else
            Icon(Icons.info_outline, size: 16, color: badgeColor),

          const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Video đã lưu",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          Text(
            "${videoPaths.length} mục",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      physics: const BouncingScrollPhysics(),
      itemCount: videoPaths.length,
      itemBuilder: (context, index) {
        final path = videoPaths[index];
        final fileName = path.split('/').last;

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VideoPlayerScreen(
                    videoPath: path,
                    videoName: fileName.replaceAll(".mp4", ""),
                  ),
                ),
              );
            },
            leading: Container(
              height: 55,
              width: 55,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5E5E), Color(0xFFFF3B30)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF3B30).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            title: Text(
              fileName.replaceAll(".mp4", ""),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "MP4",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getFileSize(path),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            trailing: _buildItemMenu(path, fileName),
          ),
        );
      },
    );
  }

  Widget _buildItemMenu(String path, String fileName) {
    return IconButton(
      icon: const Icon(Icons.more_horiz_rounded, color: Colors.black45),
      onPressed: () => _showActionSheet(path, fileName),
    );
  }

  void _showActionSheet(String path, String fileName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 35),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar tinh tế
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 25),

            // Tên file tinh gọn
            Text(
              fileName,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 30),

            // Hàng chứa các nút chức năng (Grid)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // NÚT LƯU
                _buildGridAction(
                  icon: Icons.file_download_outlined,
                  label: "Lưu vào máy",
                  color: const Color(0xFF007AFF),
                  onTap: () {
                    Navigator.pop(context);
                    saveVideoToPhotos(path);
                  },
                ),

                // NÚT XÓA
                _buildGridAction(
                  icon: Icons.delete_outline_rounded,
                  label: "Xóa video",
                  color: const Color(0xFFFF3B30),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDelete(path, fileName);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 75,
            height: 75,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1), // Nền màu pastel nhạt
              borderRadius: BorderRadius.circular(22), // Bo góc lớn hiện đại
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              Icons.videocam_outlined,
              size: 60,
              color: Colors.grey[300],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            "Bắt đầu sáng tạo!",
            style: TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Nhấn nút quay phía trên để\nkhởi tạo video đầu tiên của bạn",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String path, String fileName) {
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
              Text(
                "Bạn sắp xóa vĩnh viễn tệp:\n${fileName.replaceAll(".mp4", "")}",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
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
                        Navigator.pop(context);
                        deleteVideo(path);
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
}
