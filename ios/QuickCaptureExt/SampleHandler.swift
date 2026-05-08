import ReplayKit
import AVFoundation
import Photos

class SampleHandler: RPBroadcastSampleHandler {
    
    var assetWriter: AVAssetWriter?
    var videoInput: AVAssetWriterInput?
    var audioMicInput: AVAssetWriterInput? // Kênh thu Micro
    var audioAppInput: AVAssetWriterInput? // Kênh thu tiếng hệ thống (nhạc, game...)
    
    var isWriting = false
    var videoUrl: URL?

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        
        // 1. TÌM APP GROUP: Bắt buộc giống 100% tên Group trong tab Signing & Capabilities
        guard let sharedContainer = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.quickcapture.com") else {
            print("Lỗi: Không tìm thấy App Group")
            return
        }
        
        videoUrl = sharedContainer.appendingPathComponent("record_\(Int(Date().timeIntervalSince1970)).mp4")
        
        do {
            if FileManager.default.fileExists(atPath: videoUrl!.path) {
                try FileManager.default.removeItem(at: videoUrl!)
            }
            assetWriter = try AVAssetWriter(outputURL: videoUrl!, fileType: .mp4)
        } catch {
            print("Lỗi tạo AssetWriter")
            return
        }
        
        // 2. CẤU HÌNH HÌNH ẢNH (Bội số 16)
        let screenSize = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        var width = Int(screenSize.width * scale)
        var height = Int(screenSize.height * scale)
        width -= width % 16
        height -= height % 16
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        if assetWriter!.canAdd(videoInput!) {
            assetWriter!.add(videoInput!)
        }
        
        // 3. CẤU HÌNH ÂM THANH CHUNG (Dùng chung cho cả Mic và App)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 64000
        ]
        
        audioMicInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioMicInput?.expectsMediaDataInRealTime = true
        if assetWriter!.canAdd(audioMicInput!) {
            assetWriter!.add(audioMicInput!)
        }
        
        audioAppInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioAppInput?.expectsMediaDataInRealTime = true
        if assetWriter!.canAdd(audioAppInput!) {
            assetWriter!.add(audioAppInput!)
        }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        
        // Bắt đầu phiên ghi khi có buffer đầu tiên bay vào
        if assetWriter?.status == .unknown {
            assetWriter?.startWriting()
            assetWriter?.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            isWriting = true
        }
        
        guard isWriting, assetWriter?.status == .writing else { return }
        
        // Phân loại luồng dữ liệu để nhét vào đúng Kênh (Channel)
        if sampleBufferType == .video {
            if videoInput?.isReadyForMoreMediaData == true {
                videoInput?.append(sampleBuffer)
            }
        }
        else if sampleBufferType == .audioMic {
            if audioMicInput?.isReadyForMoreMediaData == true {
                audioMicInput?.append(sampleBuffer)
            }
        }
        else if sampleBufferType == .audioApp {
            if audioAppInput?.isReadyForMoreMediaData == true {
                audioAppInput?.append(sampleBuffer)
            }
        }
    }

   override func broadcastFinished() {
        isWriting = false
        videoInput?.markAsFinished()
        audioMicInput?.markAsFinished()
        audioAppInput?.markAsFinished()
        
        let semaphore = DispatchSemaphore(value: 0)
        
        assetWriter?.finishWriting {
            // Chỉ ghi file vào App Group, KHÔNG gọi PHPhotoLibrary ở đây
            print("Đã ghi xong file MP4 vào App Group!")
            semaphore.signal() // Mở chốt
        }
        
        // Đợi tối đa 5 giây để ghi file
        _ = semaphore.wait(timeout: .now() + 5.0)
    }
}
