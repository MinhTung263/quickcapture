import ReplayKit
import AVFoundation

class SampleHandler: RPBroadcastSampleHandler {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var isRecording = false
    private var tempVideoURL: URL?
    private var currentFileName: String = ""
    private var sessionStarted = false // Biến kiểm soát trạng thái session

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        currentFileName = "REC_\(formatter.string(from: Date())).mp4"
        // Lưu tên file vào UserDefaults App Group để App chính hoặc Extension có thể truy xuất lại nếu cần
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
            
            // Lấy kích thước màn hình chuẩn
            let screenBounds = UIScreen.main.bounds
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: screenBounds.width * UIScreen.main.scale,
                AVVideoHeightKey: screenBounds.height * UIScreen.main.scale,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6000000, // Tăng chất lượng video
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
                self.sessionStarted = false // Reset lại khi bắt đầu
            }
        } catch {
            finishBroadcastWithError(error)
        }
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard isRecording, let writer = assetWriter, let input = videoInput else { return }
        
        switch sampleBufferType {
        case .video:
            // QUAN TRỌNG: Chỉ startWriting và startSession khi nhận được buffer video đầu tiên
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

    override func broadcastFinished() {
        isRecording = false
        videoInput?.markAsFinished()
        
        assetWriter?.finishWriting { [weak self] in
            guard let self = self, let tempURL = self.tempVideoURL else { return }
            
            if let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.quickcapture.com") {
                let finalURL = sharedContainer.appendingPathComponent(self.currentFileName)
                
                do {
                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try? FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: finalURL)
                    
                    // CẬP NHẬT FLAG: Chỉ khi lưu xong xuôi mới báo có video mới
                    if let userDefaults = UserDefaults(suiteName: "group.com.quickcapture.com") {
                        userDefaults.set(true, forKey: "hasNewVideo")
                        userDefaults.set(false, forKey: "isRecordingActive")
                        userDefaults.synchronize()
                    }
                } catch {
                    print("Lỗi lưu file: \(error)")
                }
            }
        }
    }
}
