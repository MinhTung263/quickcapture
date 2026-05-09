import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../service/native_service.dart';
import '../../services/native_service.dart';
import '../../core/app_constants.dart';
import '../widgets/record_button.dart';
import '../widgets/record_panel.dart';
import '../widgets/video_card.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _native = NativeService();
  List<String> videoPaths = [];
  List<String> selectedPaths = [];
  bool isSelectionMode = false;
  bool isRecording = false;
  String status = "Sẵn sàng";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupNative();
    _loadVideos();
  }

  void _setupNative() {
    _native.channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "onVideoSaved":
          setState(() => isRecording = false);
          _loadVideos();
          break;
        case "onRecordingStarted":
          setState(() => isRecording = true);
          break;
        case "onRecordingStopped":
          setState(() => isRecording = false);
          break;
      }
      return null;
    });
  }

  Future<void> _loadVideos() async {
    final list = await _native.getVideoList();
    setState(() => videoPaths = list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        title: Text(
          isSelectionMode ? "Đã chọn ${selectedPaths.length}" : "Quick Capture",
        ),
        centerTitle: true,
        actions: [
          if (!isSelectionMode)
            IconButton(
              icon: const Icon(Icons.autorenew_rounded),
              onPressed: _loadVideos,
            )
          else
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
              onPressed: () {},
            ), // Logic xóa nhiều
        ],
      ),
      body: Column(
        children: [
          _buildTopPanel(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildTopPanel() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          RecordButton(
            isRecording: isRecording,
            onTap: () =>
                isRecording ? _native.stopRecord() : _native.startRecord(),
          ),
          const SizedBox(height: 10),
          Text(status, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: videoPaths.length,
      itemBuilder: (context, index) {
        final path = videoPaths[index];
        return VideoCard(
          path: path,
          isSelected: selectedPaths.contains(path),
          isSelectionMode: isSelectionMode,
          onTap: () {
            if (isSelectionMode) {
              setState(
                () => selectedPaths.contains(path)
                    ? selectedPaths.remove(path)
                    : selectedPaths.add(path),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoPlayerScreen(
                    videoPath: path,
                    videoName: "Video $index",
                  ),
                ),
              );
            }
          },
          onLongPress: () => setState(() {
            isSelectionMode = true;
            selectedPaths.add(path);
          }),
          onMenuPressed: () {}, // Gọi Action Sheet
        );
      },
    );
  }
}
