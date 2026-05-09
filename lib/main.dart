import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MaterialApp(home: ScreenRecordApp()));

class ScreenRecordApp extends StatefulWidget {
  const ScreenRecordApp({super.key});
  @override
  State<ScreenRecordApp> createState() => _ScreenRecordAppState();
}

class _ScreenRecordAppState extends State<ScreenRecordApp> {
  static const channel = MethodChannel('quick_capture');
  String status = "Sẵn sàng";
  List<String> videoPaths = [];

  @override
  void initState() {
    super.initState();
    loadVideoList(); // Tải danh sách video khi vừa mở app
  }

  // Bắt đầu quay
  Future<void> startRecord() async {
    try {
      final result = await channel.invokeMethod("startRecord");
      setState(() => status = result);
    } catch (e) {
      setState(() => status = "Lỗi: $e");
    }
  }

  // Tải danh sách video từ iOS
  Future<void> loadVideoList() async {
    setState(() => status = "Đang tải danh sách...");
    try {
      final List<dynamic>? paths = await channel.invokeMethod("getVideoList");
      setState(() {
        videoPaths = paths?.cast<String>() ?? [];
        status = "Đã tìm thấy ${videoPaths.length} video";
      });
    } catch (e) {
      setState(() => status = "Lỗi tải danh sách: $e");
    }
  }

  // Lưu video cụ thể vào Ảnh
  Future<void> saveVideoToPhotos(String path) async {
    setState(() => status = "Đang lưu video...");
    try {
      final result = await channel.invokeMethod(
        "saveSpecificVideo",
        {"path": path}, // Gửi đường dẫn cụ thể sang Native
      );

      if (result == "Thành công") {
        setState(() => status = "Đã thêm vào Ảnh trên iPhone!");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lưu video thành công!',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => status = result);
      }
    } catch (e) {
      setState(() => status = "Lỗi lưu video: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quick Capture List")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: startRecord,
                icon: const Icon(Icons.videocam),
                label: const Text("1. BẮT ĐẦU QUAY"),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                ),
                onPressed: loadVideoList,
                icon: const Icon(Icons.refresh),
                label: const Text("2. LÀM MỚI DS"),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(),
          // Hiển thị danh sách video
          Expanded(
            child: videoPaths.isEmpty
                ? const Center(
                    child: Text("Chưa có video nào. Hãy quay thử nhé!"),
                  )
                : ListView.builder(
                    itemCount: videoPaths.length,
                    itemBuilder: (context, index) {
                      String path = videoPaths[index];
                      String fileName = path.split('/').last; // Lấy tên file

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.video_file,
                            color: Colors.blue,
                            size: 40,
                          ),
                          title: Text(
                            fileName,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: const Text(
                            "Đã lưu cục bộ",
                            style: TextStyle(color: Colors.green, fontSize: 12),
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                            ),
                            onPressed: () => saveVideoToPhotos(path),
                            child: const Text(
                              "Lưu vào Ảnh",
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
