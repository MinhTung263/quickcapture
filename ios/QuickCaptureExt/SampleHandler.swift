import ReplayKit
import AVFoundation

class SampleHandler: RPBroadcastSampleHandler {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    
    // Luồng ghi âm thanh hệ thống (App Audio)
    private var audioAppInput: AVAssetWriterInput?
    
    private var isRecording = false
    private var tempVideoURL: URL?
    private var currentFileName: String = ""
    private var sessionStarted = false
    private var stopCheckTimer: Timer?
    
    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        currentFileName = "REC_\(formatter.string(from: Date())).mp4"
        
        if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
            userDefaults.set(currentFileName, forKey: "currentRecordingFileName")
            userDefaults.set(true, forKey: "isRecordingActive")
            userDefaults.synchronize()
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(currentFileName)
        self.tempVideoURL = tempURL
        
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        self.isRecording = true
        self.sessionStarted = false
        
        DispatchQueue.main.async {
            self.stopCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.checkForStopCommand()
            }
        }
    }
    
    private func setupWriter(with sampleBuffer: CMSampleBuffer) {
        guard let tempURL = self.tempVideoURL else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Lấy CHÍNH XÁC số lượng điểm ảnh vật lý của màn hình
        let nativeWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let nativeHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        
        var selectedQuality = "720p"
        var isAudioEnabled = true
        
        if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
            selectedQuality = userDefaults.string(forKey: "selectedVideoQuality") ?? "720p"
            if userDefaults.object(forKey: "isAudioEnabled") != nil {
                isAudioEnabled = userDefaults.bool(forKey: "isAudioEnabled")
            }
        }
        
        var finalWidth = Int(nativeWidth)
        var finalHeight = Int(nativeHeight)
        var bitRate = 10_000_000
        
        let maxDimension = max(nativeWidth, nativeHeight)
        var scaleFactor: CGFloat = 1.0
        
        switch selectedQuality {
        case "1080p":
            // CHÌA KHÓA 1: Bỏ chia 16. Chỉ làm chẵn (Mod-2) để tránh lỗi hệ màu YUV.
            // Điều này đảm bảo kích thước video khớp từng điểm ảnh (Pixel-Perfect) với màn hình thật,
            // vô hiệu hoá hoàn toàn thuật toán nội suy (nguyên nhân gây mờ chữ).
            finalWidth = (Int(nativeWidth) / 2) * 2
            finalHeight = (Int(nativeHeight) / 2) * 2
            bitRate = 20_000_000 
            
        case "480p":
            if maxDimension > 854 { scaleFactor = 854 / maxDimension }
            finalWidth = (Int(nativeWidth * scaleFactor) / 2) * 2
            finalHeight = (Int(nativeHeight * scaleFactor) / 2) * 2
            bitRate = 4_000_000
            
        default: // "720p"
            if maxDimension > 1280 { scaleFactor = 1280 / maxDimension }
            finalWidth = (Int(nativeWidth * scaleFactor) / 2) * 2
            finalHeight = (Int(nativeHeight * scaleFactor) / 2) * 2
            bitRate = 10_000_000
        }
        
        do {
            let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc, // Vẫn giữ HEVC
                AVVideoWidthKey: finalWidth,
                AVVideoHeightKey: finalHeight,
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
                
                // CHÌA KHÓA 2: Ép hệ màu chuẩn HD (Rec.709). 
                // Xóa bỏ "lớp sương mù" và hiện tượng bợt màu, giúp màu sắc rực rỡ và sâu như màn hình thật.
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                ],
                
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitRate,
                    AVVideoExpectedSourceFrameRateKey: 60,
                    AVVideoMaxKeyFrameIntervalKey: 30, // Tạo keyframe mỗi 0.5s
                    AVVideoAllowFrameReorderingKey: false
                ]
            ]
            
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                self.assetWriter = writer
                self.videoInput = input
            }
            
            // ... Setup Âm thanh (giữ nguyên) ...
            if isAudioEnabled {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVNumberOfChannelsKey: 2,
                    AVSampleRateKey: 44100,
                    AVEncoderBitRateKey: 192_000
                ]
                let appAudioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                appAudioIn.expectsMediaDataInRealTime = true
                if writer.canAdd(appAudioIn) {
                    writer.add(appAudioIn)
                    self.audioAppInput = appAudioIn
                }
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
            // Bắt khung hình đầu tiên để setup AVAssetWriter
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
            
        case .audioApp:
            // Chỉ ghi nhận khung hình âm thanh nếu audioAppInput đã được khởi tạo
            guard let writer = assetWriter, let input = audioAppInput else { return }
            if writer.status == .writing && input.isReadyForMoreMediaData && sessionStarted {
                input.append(sampleBuffer)
            }
            
        // Bỏ qua .audioMic hoàn toàn
        @unknown default:
            break
        }
    }
    
    private func forceStopAndSave() {
        isRecording = false
        
        videoInput?.markAsFinished()
        audioAppInput?.markAsFinished()
        
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
        audioAppInput?.markAsFinished()
        
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
