import UIKit
import Flutter
import ReplayKit
import AVFoundation
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    var assetWriter: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var audioInput: AVAssetWriterInput?
    var isRecording = false
    var videoUrl: URL?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // 1. Đăng ký plugin
        GeneratedPluginRegistrant.register(with: self)
        
        // 2. Lấy luồng giao tiếp thẳng từ Registrar (Tuyệt đối an toàn, không lo văng app)
        let registrar = self.registrar(forPlugin: "QuickCaptureApp")!
        let channel = FlutterMethodChannel(name: "quick_capture", binaryMessenger: registrar.messenger())
        
        // 3. Đăng ký lắng nghe sự kiện
        channel.setMethodCallHandler { [weak self] (call, result) in
                        guard let self = self else { return }
                        
                        if call.method == "startRecord" {
                            self.startRecording(result: result)
                        }
                        else if call.method == "stopRecord" {
                            // Khi dùng Broadcast, iOS không cho phép tắt bằng code từ app chính.
                            // Người dùng phải tự bấm vào thanh màu đỏ trên cùng màn hình iPhone để dừng.
                            // Khi dừng, Extension sẽ tự động chạy code lưu file vào Ảnh.
                            result("Hãy chạm vào biểu tượng màu đỏ trên thanh trạng thái (góc trên màn hình) để dừng quay.")
                        }
                        else if call.method == "saveVideoFromExtension" {
                            self.saveVideoFromAppGroup(result: result)
                        }
                        
                        else {
                            result(FlutterMethodNotImplemented)
                        }
                    }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    func startRecording(result: @escaping FlutterResult) {
            // Tạo view picker của Apple ẩn dưới nền
            let broadcastPicker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
            
            // ⚠️ QUAN TRỌNG: ĐIỀN ĐÚNG BUNDLE ID CỦA CÁI EXTENSION BẠN VỪA TẠO TRONG XCODE VÀO ĐÂY
            broadcastPicker.preferredExtension = "group.com.quickcapture.com"
            broadcastPicker.showsMicrophoneButton = true // Cho phép user chọn bật/tắt mic hệ thống
            
            // Mẹo mô phỏng thao tác bấm để hiện thẳng popup lên màn hình
            if let button = broadcastPicker.subviews.first(where: { $0 is UIButton }) as? UIButton {
                button.sendActions(for: .allEvents)
                result(nil)
            } else {
                result(FlutterError(code: "ERR", message: "Không mở được công cụ quay hệ thống", details: nil))
            }
        }
    func stopRecording(result: @escaping FlutterResult) {
        if !isRecording {
            result(FlutterError(code: "NOT_RECORDING", message: "Chưa quay màn hình", details: nil))
            return
        }
        
        let recorder = RPScreenRecorder.shared()
        recorder.stopCapture { error in
            self.isRecording = false
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            
            self.assetWriter?.finishWriting {
                if let error = error {
                    result(FlutterError(code: "STOP_ERROR", message: error.localizedDescription, details: nil))
                    return
                }
                
                guard let url = self.videoUrl else {
                    result(FlutterError(code: "URL_ERROR", message: "Không tìm thấy đường dẫn video", details: nil))
                    return
                }
                
                // Lưu thẳng vào Thư viện ảnh (Gallery) của iOS
                PHPhotoLibrary.requestAuthorization { status in
                    if #available(iOS 14, *) {
                        if status == .authorized || status == .limited {
                            PHPhotoLibrary.shared().performChanges({
                                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                            }) { saved, error in
                                DispatchQueue.main.async {
                                    if saved {
                                        result("Đã lưu vào Ảnh (Photos) iOS")
                                    } else {
                                        // BÁO LỖI THỰC TẾ RA MÀN HÌNH FLUTTER
                                        let errorMessage = error?.localizedDescription ?? "Lỗi hệ thống không xác định"
                                        result("Lỗi lưu Ảnh: \(errorMessage)")
                                    }
                                }
                            }
                        } else {
                            DispatchQueue.main.async {
                                result("Chưa cấp quyền Ảnh. File tạm: \(url.path)")
                            }
                        }
                    } else {
                        // Fallback on earlier versions
                    }
                }
            }
        }
    }
    func saveVideoFromAppGroup(result: @escaping FlutterResult) {
            // Trỏ đúng vào App Group của bạn
            guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.quickcapture.com") else {
                result(FlutterError(code: "ERR", message: "Không tìm thấy App Group", details: nil))
                return
            }
            
            do {
                let files = try FileManager.default.contentsOfDirectory(at: sharedContainer, includingPropertiesForKeys: nil)
                // Lọc ra các file MP4
                let videoFiles = files.filter { $0.pathExtension == "mp4" }
                
                if videoFiles.isEmpty {
                    result("Không tìm thấy video nào vừa quay.")
                    return
                }
                
                // Lấy file mới nhất
                if let latestVideo = videoFiles.sorted(by: { $0.path > $1.path }).first {
                    
                    // Dùng App Chính để lưu vào Ảnh (An toàn 100%)
                    PHPhotoLibrary.requestAuthorization { status in
                        if #available(iOS 14, *) {
                            if status == .authorized || status == .limited {
                                PHPhotoLibrary.shared().performChanges({
                                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: latestVideo)
                                }) { saved, error in
                                    if saved {
                                        // Xoá file tạm trong App Group cho nhẹ máy
                                        try? FileManager.default.removeItem(at: latestVideo)
                                        DispatchQueue.main.async { result("✅ Đã chép video vào Ảnh thành công!") }
                                    } else {
                                        DispatchQueue.main.async { result("❌ Lỗi lưu ảnh: \(error?.localizedDescription ?? "")") }
                                    }
                                }
                            } else {
                                DispatchQueue.main.async { result("❌ App chưa có quyền truy cập Ảnh") }
                            }
                        } else {
                            // Fallback on earlier versions
                        }
                    }
                }
            } catch {
                result(FlutterError(code: "ERR", message: "Lỗi đọc thư mục App Group", details: nil))
            }
        }
}
