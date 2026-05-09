import 'package:flutter/services.dart';
import 'package:quickcapture/core/constants.dart';

class NativeService {
  static final NativeService _instance = NativeService._internal();
  factory NativeService() => _instance;
  NativeService._internal();

  final MethodChannel _channel = AppConstants.channel;
  MethodChannel get channel => _channel;

  Future<String?> startRecord() async =>
      await _channel.invokeMethod("startRecord");
  Future<String?> stopRecord() async =>
      await _channel.invokeMethod("stopRecord");

  Future<List<String>> getVideoList() async {
    final List<dynamic>? paths = await _channel.invokeMethod("getVideoList");
    return paths?.cast<String>() ?? [];
  }

  Future<bool> deleteVideo(String path) async {
    return await _channel.invokeMethod("deleteVideo", {"path": path});
  }

  Future<String> saveToPhotos(String path) async {
    return await _channel.invokeMethod("saveSpecificVideo", {"path": path});
  }

  Future<bool> checkNewVideoStatus() async =>
      await _channel.invokeMethod("checkNewVideoStatus");
  Future<bool> isRecording() async =>
      await _channel.invokeMethod("isRecording");
}
