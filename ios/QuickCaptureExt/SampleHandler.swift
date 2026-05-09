import ReplayKit
import AVFoundation

class SampleHandler: RPBroadcastSampleHandler {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var isRecording = false
    
    // Đường dẫn file TẠM THỜI (trong nội bộ Extension)
    private var tempVideoURL: URL?
    
    // Tên file để sau này copy sang App Group
    private var currentFileName: String = ""

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        // 1. Tạo tên file duy nhất theo thời gian
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        currentFileName = "REC_\(formatter.string(from: Date())).mp4"
        
        // 2. SỬA LỖI TẠI ĐÂY: Ghi vào thư mục TEMP nội bộ thay vì App Group
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(currentFileName)
        self.tempVideoURL = tempURL
        
        // Xóa file temp nếu vô tình bị trùng
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        do {
            // Khởi tạo ghi file tại thư mục Temp (Đảm bảo 100% iOS không báo lỗi URL)
            let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
            
            let screenWidth = Int(UIScreen.main.bounds.width * UIScreen.main.scale)
            let screenHeight = Int(UIScreen.main.bounds.height * UIScreen.main.scale)
            
            // Ép kích thước về số chẵn
            let validWidth = screenWidth - (screenWidth % 16)
            let validHeight = screenHeight - (screenHeight % 16)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: validWidth,
                AVVideoHeightKey: validHeight
            ]
            
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            input.expectsMediaDataInRealTime = true
            
            if writer.canAdd(input) {
                writer.add(input)
            } else {
                finishBroadcastWithError(NSError(domain: "SampleHandler", code: -2, userInfo: [NSLocalizedDescriptionKey: "Không thể thêm đầu vào video."]))
                return
            }
            
            if writer.startWriting() {
                self.assetWriter = writer
                self.videoInput = input
                self.isRecording = true
            } else {
                let errorMsg = writer.error?.localizedDescription ?? "Lỗi không xác định"
                finishBroadcastWithError(NSError(domain: "SampleHandler", code: -3, userInfo: [NSLocalizedDescriptionKey: "Writer không thể bắt đầu: \(errorMsg)"]))
            }
        } catch {
            finishBroadcastWithError(error)
        }
    }
    
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard isRecording, let writer = assetWriter else { return }
        
        switch sampleBufferType {
        case .video:
            if writer.status == .unknown {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startSession(atSourceTime: pts)
            }
            if writer.status == .writing && videoInput?.isReadyForMoreMediaData == true {
                videoInput?.append(sampleBuffer)
            }
        default: break
        }
    }

    override func broadcastFinished() {
        isRecording = false
        videoInput?.markAsFinished()
        
        // 3. XỬ LÝ COPY FILE SAU KHI GHI XONG
        assetWriter?.finishWriting { [weak self] in
            guard let self = self, let tempURL = self.tempVideoURL else { return }
            
            // Lấy đường dẫn App Group
            guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.quickcapture.com") else {
                print("Lỗi: Không tìm thấy App Group để copy file sang.")
                return
            }
            
            // Đảm bảo thư mục App Group tồn tại
            try? FileManager.default.createDirectory(at: sharedContainer, withIntermediateDirectories: true, attributes: nil)
            
            let finalURL = sharedContainer.appendingPathComponent(self.currentFileName)
            
            do {
                // Di chuyển file từ thư mục Temp sang thư mục App Group
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: finalURL)
                print("Thành công: Đã chuyển file sang App Group tại \(finalURL.path)")
            } catch {
                print("Lỗi copy file: \(error.localizedDescription)")
            }
        }
    }
}
