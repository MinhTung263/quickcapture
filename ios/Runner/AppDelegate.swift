import UIKit
import Flutter
import Photos
import ReplayKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // 1. Đăng ký plugin
        GeneratedPluginRegistrant.register(with: self)
        
        // 2. Lấy luồng giao tiếp thẳng từ Registrar
        let registrar = self.registrar(forPlugin: "QuickCaptureApp")!
        let channel = FlutterMethodChannel(name: "quick_capture", binaryMessenger: registrar.messenger())
        
        channel.setMethodCallHandler({ (call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "startRecord":
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
                
            default:
                result(FlutterMethodNotImplemented)
            }
        })
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
