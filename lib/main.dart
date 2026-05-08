import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const channel = MethodChannel("quick_capture");

  String status = "Idle";

  Future<void> startRecord() async {
    try {
      await channel.invokeMethod("startRecord");

      setState(() {
        status = "Đang mở trình quay màn hình...";
      });
    } on PlatformException catch (e) {
      setState(() {
        status = "Lỗi: ${e.message}";
      });
      print(e);
    } catch (e) {
      print(e);
    }
  }

  Future<void> stopRecord() async {
    try {
      final result = await channel.invokeMethod("stopRecord");

      setState(() {
        // Sẽ in ra dòng hướng dẫn tắt qua thanh trạng thái màu đỏ của iOS
        // Hoặc xử lý trả về đường dẫn nếu bạn đang chạy Android
        status = result.toString();
      });
    } catch (e) {
      print(e);
    }
  }

  // --- HÀM MỚI: LẤY VIDEO TỪ APP GROUP CHÉP VÀO ẢNH ---
  Future<void> saveVideoToGallery() async {
    try {
      setState(() {
        status = "Đang xử lý và lưu video...";
      });

      // 2. Gọi hàm Native iOS để gom file
      final result = await channel.invokeMethod("saveVideoFromExtension");

      setState(() {
        status = result.toString();
      });
    } catch (e) {
      setState(() {
        status = "Lỗi lấy video: $e";
      });
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text("Flutter Screen Recorder")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 30),

              ElevatedButton(
                onPressed: startRecord,
                child: const Text("1. BẮT ĐẦU QUAY"),
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: stopRecord,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text("2. DỪNG QUAY (Hoặc bấm thanh màu đỏ)"),
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: saveVideoToGallery,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text("3. LƯU VIDEO VÀO ẢNH (Chỉ iOS)"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
