import UIKit
import Flutter
import Photos
import ReplayKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    var channel: FlutterMethodChannel?
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // 1. Đăng ký plugin
        GeneratedPluginRegistrant.register(with: self)
        // 🚀 DỌN DẸP CỜ CŨ LÚC KHỞI ĐỘNG APP
        if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
            userDefaults.set(false, forKey: "hasNewVideo")
            userDefaults.synchronize()
        }
        // 2. Lấy luồng giao tiếp thẳng từ Registrar
        let registrar = self.registrar(forPlugin: "QuickCaptureApp")!
        channel = FlutterMethodChannel(name: "quick_capture", binaryMessenger: registrar.messenger())
        
        channel?.setMethodCallHandler({ (call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "startRecord":
                // 1. Nhận tham số quality từ Flutter (nếu không có thì mặc định 720p)
                let args = call.arguments as? [String: Any]
                let quality = args?["quality"] as? String ?? "720p"
                
                // 2. Lưu chất lượng vào App Group để Extension có thể đọc được
                if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
                    userDefaults.set(quality, forKey: "selectedVideoQuality")
                    userDefaults.synchronize()
                }
                if #available(iOS 12.0, *) {
                    DispatchQueue.main.async {
                        // Lấy cửa sổ giao diện hiện tại của App
                        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else {
                            result("Lỗi: Không tìm thấy giao diện")
                            return
                        }
                        
                        // 1. Tạo Picker với kích thước thật (thay vì .zero)
                        let pickerView = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
                        pickerView.showsMicrophoneButton = false
                        pickerView.preferredExtension = "com.quickcapture.vn.QuickCaptureExt" // Bundle ID của bạn
                        
                        // 2. Ép nó phải ẩn đi (để user không thấy) nhưng VẪN NẰM TRONG VIEW HIERARCHY
                        pickerView.alpha = 0.01
                        window.addSubview(pickerView)
                        
                        // 3. Thực hiện click giả
                        for view in pickerView.subviews {
                            if let button = view as? UIButton {
                                button.sendActions(for: .touchUpInside) // Dùng touchUpInside thay vì allEvents
                                break
                            }
                        }
                        
                        // 4. Dọn dẹp: Xóa nút mồi này đi sau 1 giây để không rác bộ nhớ
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            pickerView.removeFromSuperview()
                        }
                    }
                    result("Đang mở trình quay...")
                } else {
                    result("iOS không hỗ trợ")
                }
                
            case "getVideoList":
                self.getVideoList(result: result)
                
            case "saveSpecificVideo":
                if let args = call.arguments as? [String: Any], let path = args["path"] as? String {
                    self.saveSpecificVideo(path: path, result: result)
                } else {
                    result("Lỗi: Không nhận được đường dẫn video")
                }
            case "deleteVideo" :
                // Lấy đường dẫn file từ đối số truyền vào
                guard let args = call.arguments as? [String: Any],
                      let filePath = args["path"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENTS", message: "Path is missing", details: nil))
                    return
                }
                
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: filePath) {
                    do {
                        try fileManager.removeItem(atPath: filePath)
                        result(true) // Xóa thành công
                    } catch {
                        result(FlutterError(code: "DELETE_FAILED", message: "Could not delete file", details: error.localizedDescription))
                    }
                } else {
                    result(false) // File không tồn tại
                }
            case "checkNewVideoStatus":
                if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
                    let hasNew = userDefaults.bool(forKey: "hasNewVideo")
                    if hasNew {
                        userDefaults.set(false, forKey: "hasNewVideo") // Reset flag
                        userDefaults.synchronize()
                    }
                    result(hasNew)
                } else {
                    result(false)
                }
            case "isRecording":
                if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
                    let isRecording = userDefaults.bool(forKey: "isRecordingActive")
                    result(isRecording)
                } else {
                    result(false)
                }
            case "stopRecord":
                // Ghi mật lệnh ép dừng vào App Group để Extension đọc được
                if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
                    userDefaults.set(true, forKey: "forceStopCommand")
                    userDefaults.synchronize()
                }
                // Trả về cho Flutter biết
                result("IOS_FORCE_STOPPING")
                
            default:
                result(FlutterMethodNotImplemented)
            }
        })
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenCaptureStateChanged),
            name: UIScreen.capturedDidChangeNotification,
            object: nil
        )
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    // 🚀 HÀM GỬI TÍN HIỆU SANG FLUTTER KHI TRẠNG THÁI MÀN HÌNH THAY ĐỔI
    @objc func screenCaptureStateChanged() {
        if UIScreen.main.isCaptured {
            // Thanh đỏ hiện lên -> Bắt đầu quay
            channel?.invokeMethod("onRecordingStarted", arguments: nil)
        } else {
            // Thanh đỏ đã biến mất -> Dừng quay
            if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
                let hasNew = userDefaults.bool(forKey: "hasNewVideo")
                if hasNew {
                    // Reset cờ và báo cho Flutter load video
                    userDefaults.set(false, forKey: "hasNewVideo")
                    userDefaults.synchronize()
                    channel?.invokeMethod("onVideoSaved", arguments: nil)
                } else {
                    // Tắt quay nhưng không có video (do hủy hoặc lỗi)
                    channel?.invokeMethod("onRecordingStopped", arguments: nil)
                }
            } else {
                channel?.invokeMethod("onRecordingStopped", arguments: nil)
            }
        }
    }
    private func getVideoList(result: @escaping FlutterResult) {
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.quickcapture.com") else {
            result([])
            return
        }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: sharedContainer, includingPropertiesForKeys: [.creationDateKey])
            let videoPaths = fileURLs
                .filter { $0.pathExtension == "mp4" }
                .sorted { u1, u2 in
                    let date1 = (try? u1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let date2 = (try? u2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return date1 > date2
                }
                .map { $0.path }
            
            result(videoPaths)
        } catch {
            result([])
        }
    }
    
    private func saveSpecificVideo(path: String, result: @escaping FlutterResult) {
        let videoURL = URL(fileURLWithPath: path)
        
        if !FileManager.default.fileExists(atPath: path) {
            result("Không tìm thấy file video này.")
            return
        }
        
        
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                }) { success, error in
                    if success {
                        result("Thành công")
                    } else {
                        result("Lỗi lưu ảnh: \(error?.localizedDescription ?? "Không xác định")")
                    }
                }
            } else {
                result("Ứng dụng cần quyền truy cập Ảnh.")
            }
        }
    }
}
