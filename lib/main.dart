import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const QuickCaptureApp());

class QuickCaptureApp extends StatelessWidget {
  const QuickCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed:
            Colors.redAccent, // Đổi màu chủ đạo sang đỏ (màu của record)
        brightness: Brightness.light,
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

// Thêm WidgetsBindingObserver để theo dõi trạng thái app
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
    // Đăng ký quan sát vòng đời ứng dụng
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
              isRecording = false; // 🚀 Trả nút về trạng thái Bắt đầu
              status = "Đã lưu video! Đang làm mới...";
            });
            await loadVideoList();
          }
          break;
        // Rất dễ dàng thêm các tín hiệu khác từ Android/iOS ở đây sau này
        // case "onError": ...
        case "onRecordingStarted":
          if (mounted) {
            setState(() {
              isRecording = true;
              status = "🔴 Đang ghi hình...";
            });
          }
          break;

        // 🚀 THÊM CASE NÀY: Xử lý khi thanh đỏ tắt nhưng không có video
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
      return null; // Chuẩn hóa bắt buộc của MethodCallHandler
    });
  }

  @override
  void dispose() {
    // Hủy đăng ký khi widget bị hủy
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
      // 1. Kiểm tra xem Native có cắm cờ "Có video mới" không (Dùng cho iOS hoặc khi thoát app hẳn)
      final bool hasNew = await channel.invokeMethod("checkNewVideoStatus");

      if (hasNew) {
        if (mounted) {
          setState(() => isRecording = false); // 🚀 Đảm bảo reset nút
        }
        // NẾU THỰC SỰ CÓ VIDEO MỚI -> MỚI ĐƯỢC XOAY LOADING
        loadVideoList();
      } else {
        // 2. NẾU KHÔNG CÓ VIDEO MỚI -> Chỉ cập nhật lại chữ hiển thị trạng thái
        final bool recording = await channel.invokeMethod("isRecording");

        if (mounted) {
          setState(() {
            isRecording = recording; // 🚀 Cập nhật trạng thái nút theo hệ thống
            if (isRecording) {
              status = "🔴 Đang ghi hình...";
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
      if (!status.contains("Đã lưu")) status = "Đang quét video...";
    });

    await Future.delayed(const Duration(milliseconds: 1500));

    try {
      final List<dynamic>? paths = await channel.invokeMethod("getVideoList");
      if (mounted) {
        setState(() {
          videoPaths = paths?.cast<String>() ?? [];
          status = videoPaths.isEmpty
              ? "Chưa có video"
              : "Tìm thấy ${videoPaths.length} video";
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
        _showSnackBar("Đã thêm vào Thư viện ảnh!");
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
        if (mounted) {
          setState(() {
            // Chỉ hiển thị trạng thái chờ, tuyệt đối không tự loadVideoList ở đây nữa
            status = "Đang chờ iOS đóng gói video...";
          });
        }
      } else {
        // Xử lý cho Android
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
        _showSnackBar("Đã xóa video");
        loadVideoList();
      }
    } catch (e) {
      _showSnackBar("Lỗi: $e", isError: true);
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showLoadingDialog(String text) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Row(
          children: [
            const CircularProgressIndicator(strokeWidth: 3),
            const SizedBox(width: 20),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7), // Màu nền nhẹ kiểu iOS
      appBar: AppBar(
        title: const Text(
          "Quick Capture",
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        actions: [
          isLoading
              ? const Padding(
                  padding: EdgeInsets.only(right: 15),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: loadVideoList,
                ),
        ],
      ),
      body: Column(
        children: [
          // Header Panel
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 25),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildStatusBadge(),
                const SizedBox(height: 20),
                _buildRecordPanel(),
              ],
            ),
          ),

          // List Area
          Expanded(
            child: videoPaths.isEmpty ? _buildEmptyState() : _buildVideoList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isLoading
            ? Colors.orange.withOpacity(0.1)
            : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLoading ? Icons.sync : Icons.info_outline,
            size: 16,
            color: isLoading ? Colors.orange : Colors.blue,
          ),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              color: isLoading ? Colors.orange[800] : Colors.blue[800],
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
      ),
      child: Column(
        children: [
          Text(
            status,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),

          // 🚀 LOGIC ĐỔI GIAO DIỆN NÚT BẤM
          ElevatedButton.icon(
            onPressed: isRecording ? stopRecord : startRecord,
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecording
                  ? Colors.grey[800]
                  : Colors.redAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 55),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              elevation: isRecording ? 1 : 4,
            ),
            icon: Icon(
              isRecording ? Icons.stop_rounded : Icons.fiber_manual_record,
            ),
            label: Text(
              isRecording ? "DỪNG GHI HÌNH" : "BẮT ĐẦU GHI HÌNH",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(15, 20, 15, 10),
      itemCount: videoPaths.length,
      itemBuilder: (context, index) {
        final path = videoPaths[index];
        final fileName = path.split('/').last;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withOpacity(0.05)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              height: 50,
              width: 50,
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.play_circle_filled_rounded,
                color: Colors.redAccent,
                size: 32,
              ),
            ),
            title: Text(
              fileName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: const Text(
              "Tệp video cục bộ • .mp4",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: _buildItemMenu(path, fileName),
          ),
        );
      },
    );
  }

  Widget _buildItemMenu(String path, String fileName) {
    return PopupMenuButton<String>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      onSelected: (val) {
        if (val == 'save') saveVideoToPhotos(path);
        if (val == 'delete') _confirmDelete(path, fileName);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'save',
          child: Row(
            children: [
              Icon(Icons.save_alt_rounded, size: 20),
              SizedBox(width: 10),
              Text("Lưu vào Ảnh"),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
              SizedBox(width: 10),
              Text("Xóa", style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Icon(
              Icons.video_collection_outlined,
              size: 80,
              color: Colors.grey[300],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Chưa có video nào",
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Nhấn nút trên để bắt đầu quay phim",
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String path, String fileName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Xác nhận xóa"),
        content: Text("Bạn muốn xóa vĩnh viễn tệp:\n$fileName?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              deleteVideo(path);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[50],
              foregroundColor: Colors.red,
              elevation: 0,
            ),
            child: const Text("Xóa"),
          ),
        ],
      ),
    );
  }
}
