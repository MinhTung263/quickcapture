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
        
        // KHÔNG khởi tạo AVAssetWriter ở đây nữa để tránh lỗi sai kích thước màn hình
        self.isRecording = true
        self.sessionStarted = false
        
        DispatchQueue.main.async {
            self.stopCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkForStopCommand()
            }
        }
    }
    
    // 🚀 HÀM KHỞI TẠO WRITER - GIỮ NGUYÊN CHẤT LƯỢNG GỐC 100%
    private func setupWriter(with sampleBuffer: CMSampleBuffer) {
        guard let tempURL = self.tempVideoURL else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // 1. Lấy độ phân giải GỐC THỰC TẾ của thiết bị từ ReplayKit
        let nativeWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let nativeHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        
        // 2. Đọc cấu hình từ Flutter
        var selectedQuality = "720p"
        if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
            selectedQuality = userDefaults.string(forKey: "selectedVideoQuality") ?? "720p"
        }
        
        var finalWidth = Int(nativeWidth)
        var finalHeight = Int(nativeHeight)
        var bitRate = 5000000
        
        let maxDimension = max(nativeWidth, nativeHeight)
        var scaleFactor: CGFloat = 1.0
        
        // 3. Xử lý Logic Scale & Bitrate
        switch selectedQuality {
        case "1080p":
            // 🔥 CHÌA KHÓA GIỮ NGUYÊN CHẤT LƯỢNG GỐC
            // Tuyệt đối không chia 16, chỉ đảm bảo là số chẵn (/ 2 * 2) để tránh lỗi dải màu
            finalWidth = (Int(nativeWidth) / 2) * 2
            finalHeight = (Int(nativeHeight) / 2) * 2
            
            // Cấp Bitrate hạng nặng: Nhân 7.0 để Video hoàn toàn không vỡ hạt kể cả khi chuyển cảnh nhanh
            let totalPixels = nativeWidth * nativeHeight
            bitRate = Int(totalPixels * 7.0)
            
        case "480p":
            if maxDimension > 854 { scaleFactor = 854 / maxDimension }
            finalWidth = (Int(nativeWidth * scaleFactor) / 16) * 16
            finalHeight = (Int(nativeHeight * scaleFactor) / 16) * 16
            bitRate = 2500000 // 2.5 Mbps
            
        default: // "720p"
            if maxDimension > 1280 { scaleFactor = 1280 / maxDimension }
            finalWidth = (Int(nativeWidth * scaleFactor) / 16) * 16
            finalHeight = (Int(nativeHeight * scaleFactor) / 16) * 16
            bitRate = 5000000 // 5 Mbps
        }
        
        do {
            let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: finalWidth,
                AVVideoHeightKey: finalHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitRate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, // Cấu hình cao nhất
                    AVVideoExpectedSourceFrameRateKey: 60, // Khóa ở 60 FPS
                    AVVideoMaxKeyFrameIntervalKey: 60 // Giúp file video tua mượt hơn, nét hơn
                ]
            ]
            
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            
            if writer.canAdd(input) {
                writer.add(input)
                self.assetWriter = writer
                self.videoInput = input
            }
        } catch {
            print("Lỗi khởi tạo Writer: \(error)")
        }
    }
    
    @objc private func checkForStopCommand() {
        if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com"),
           userDefaults.bool(forKey: "forceStopCommand") {
            
            userDefaults.set(false, forKey: "forceStopCommand")
            userDefaults.synchronize()
            
            stopCheckTimer?.invalidate()
            stopCheckTimer = nil
            
            forceStopAndSave()
        }
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard isRecording else { return }
        
        switch sampleBufferType {
        case .video:
            // 🚀 BẮT ĐÚNG KHUNG HÌNH ĐẦU TIÊN ĐỂ KHỞI TẠO WRITER
            if assetWriter == nil {
                setupWriter(with: sampleBuffer)
            }
            
            guard let writer = assetWriter, let input = videoInput else { return }
            
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
                        
                        if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
                            userDefaults.set(true, forKey: "hasNewVideo")
                            userDefaults.set(false, forKey: "isRecordingActive")
                            userDefaults.synchronize()
                        }
                    } catch {
                        print("❌ Lỗi lưu file: \(error)")
                    }
                }
            }
            
            _ = semaphore.wait(timeout: .now() + 5.0)
        } else {
            if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
                userDefaults.set(false, forKey: "isRecordingActive")
                userDefaults.synchronize()
            }
        }
    }
}
