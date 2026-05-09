import ReplayKit
import AVFoundation

class SampleHandler: RPBroadcastSampleHandler {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var isRecording = false
    private var tempVideoURL: URL?
    private var currentFileName: String = ""
    private var sessionStarted = false
    private var stopCheckTimer: Timer?
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        currentFileName = "REC_\(formatter.string(from: Date())).mp4"
        
        // Lưu tên file vào UserDefaults App Group
        if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
            userDefaults.set(currentFileName, forKey: "currentRecordingFileName")
            userDefaults.set(true, forKey: "isRecordingActive") // Đánh dấu đang quay
            userDefaults.synchronize()
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(currentFileName)
        self.tempVideoURL = tempURL
        
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        do {
            let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
            
            // Lấy kích thước màn hình
            let screenBounds = UIScreen.main.bounds
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: screenBounds.width * UIScreen.main.scale,
                AVVideoHeightKey: screenBounds.height * UIScreen.main.scale,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6000000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            
            if writer.canAdd(input) {
                writer.add(input)
                self.assetWriter = writer
                self.videoInput = input
                self.isRecording = true
                self.sessionStarted = false
            }
        } catch {
            finishBroadcastWithError(error)
        }
        DispatchQueue.main.async {
            self.stopCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkForStopCommand()
            }
        }
    }
    @objc private func checkForStopCommand() {
        if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com"),
           userDefaults.bool(forKey: "forceStopCommand") {
            
            // Xóa lệnh
            userDefaults.set(false, forKey: "forceStopCommand")
            userDefaults.synchronize()
            
            // Hủy timer
            stopCheckTimer?.invalidate()
            stopCheckTimer = nil
            
            // Gọi hàm ép dừng đã viết lần trước
            forceStopAndSave()
        }
    }
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard isRecording, let writer = assetWriter, let input = videoInput else { return }
        
        switch sampleBufferType {
        case .video:
            if writer.status == .unknown {
                if writer.startWriting() {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    writer.startSession(atSourceTime: pts)
                    sessionStarted = true
                }
            }
            
            if writer.status == .writing && input.isReadyForMoreMediaData && sessionStarted {
                input.append(sampleBuffer)
            }
        default: break
        }
    }
    // 3. THÊM HÀM MỚI NÀY VÀO TRONG CLASS SampleHandler
    private func forceStopAndSave() {
        isRecording = false
        videoInput?.markAsFinished()
        
        if let writer = assetWriter, writer.status == .writing {
            let semaphore = DispatchSemaphore(value: 0)
            
            writer.finishWriting { [weak self] in
                defer { semaphore.signal() }
                guard let self = self, let tempURL = self.tempVideoURL else { return }
                
                if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.quickcapture.com") {
                    let finalURL = sharedContainer.appendingPathComponent(self.currentFileName)
                    
                    do {
                        if FileManager.default.fileExists(atPath: finalURL.path) {
                            try? FileManager.default.removeItem(at: finalURL)
                        }
                        try FileManager.default.moveItem(at: tempURL, to: finalURL)
                        
                        // Bật cờ báo có video mới
                        if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
                            userDefaults.set(true, forKey: "hasNewVideo")
                            userDefaults.set(false, forKey: "isRecordingActive")
                            userDefaults.synchronize()
                        }
                    } catch {
                        print("Lỗi ép lưu: \(error)")
                    }
                }
            }
            
            _ = semaphore.wait(timeout: .now() + 5.0)
        }
        
        // ĐÂY LÀ ĐÒN QUYẾT ĐỊNH: Quăng một lỗi giả để hệ thống iOS tự dập tắt cái Extension này đi
        let error = NSError(domain: "QuickCapture", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: "Đã lưu video thành công qua App."])
        self.finishBroadcastWithError(error)
    }
    override func broadcastFinished() {
        isRecording = false
        videoInput?.markAsFinished()
        stopCheckTimer?.invalidate()
        stopCheckTimer = nil
        guard let writer = assetWriter else { return }
        
        if writer.status == .writing {
            // SỬ DỤNG SEMAPHORE ĐỂ CHẶN TIẾN TRÌNH LẠI
            let semaphore = DispatchSemaphore(value: 0)
            
            writer.finishWriting { [weak self] in
                // defer đảm bảo semaphore luôn được gọi giải phóng dù code thành công hay lỗi
                defer { semaphore.signal() }
                
                guard let self = self, let tempURL = self.tempVideoURL else { return }
                
                if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.quickcapture.com") {
                    let finalURL = sharedContainer.appendingPathComponent(self.currentFileName)
                    
                    do {
                        if FileManager.default.fileExists(atPath: finalURL.path) {
                            try? FileManager.default.removeItem(at: finalURL)
                        }
                        try FileManager.default.moveItem(at: tempURL, to: finalURL)
                        
                        if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
                            userDefaults.set(true, forKey: "hasNewVideo")
                            userDefaults.set(false, forKey: "isRecordingActive")
                            userDefaults.synchronize()
                        }
                        print("✅ Lưu thành công: \(finalURL.path)")
                    } catch {
                        print("❌ Lỗi lưu file: \(error)")
                    }
                }
            }
            
            // Ép hệ thống chờ tiến trình finishWriting hoàn tất.
            // Giới hạn timeout 5 giây để tránh bị Apple crash do freeze quá lâu.
            _ = semaphore.wait(timeout: .now() + 5.0)
        } else {
            // Nếu có lỗi, reset trạng thái
            if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
                userDefaults.set(false, forKey: "isRecordingActive")
                userDefaults.synchronize()
            }
        }
    }
}
