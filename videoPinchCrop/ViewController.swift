//
//  ViewController.swift
//  videoPinchCrop
//
//  Created by Junaid on 15/11/2021.
//

import UIKit
import AVFoundation

class ViewController: AssetSelectionViewController{
    
    @IBOutlet weak var upperView : UIView!
    @IBOutlet weak var videoCropView: VideoCropView!
    let alert = UIAlertController(title: nil, message: "Please wait...", preferredStyle: .alert)
    
    var imagePickerController = UIImagePickerController()
    var videoURL: URL?
    
    var player: AVPlayer!
    var playerLayer: AVPlayerLayer!
    var url:URL!
    
    var isPlaying: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loadLibrary()
        videoCropView.setAspectRatio(CGSize(width: 3, height: 2), animated: false)
        
    }
    
    
    @IBAction func selectAsset(_ sender: Any) {
        loadAssetRandomly()
        
        self.pinchOp()
        self.pinchOp()
        
        self.upperView.isHidden = true
    }
    
    override func loadAsset(_ asset: AVAsset) {
        videoCropView.asset = asset
    }
    
    @IBAction func pinch(_ sender: Any) {
        pinchOp()
    }
    
    func pinchOp(){
        let newRatio = videoCropView.aspectRatio.width < videoCropView.aspectRatio.height ? CGSize(width: 3, height: 2) :
            CGSize(width: 2, height: 3)
        videoCropView.setAspectRatio(newRatio, animated: true)
    }
    
    
    @objc func pinchedView(sender: UIPinchGestureRecognizer) {
        if sender.scale > 1 {
            print("Zoom out")
        } else{
            print("Zoom in")
        }
    }
    
    @IBAction func generateVideo(sender: UIButton) {
        if let asset = videoCropView.asset {
            
            DispatchQueue.main.async {
                self.showLoader()
            }
            
            try? prepareAssetComposition()
        }
    }
    
    func prepareAssetComposition() throws {
        
        guard let asset = videoCropView.asset, let videoTrack = asset.tracks(withMediaType: AVMediaType.video).first else {
            return
        }
        
        let assetComposition = AVMutableComposition()
        //        let frame1Time = CMTime(seconds: 0.2, preferredTimescale: asset.duration.timescale)
        let frame1Time = CMTime(seconds: asset.duration.seconds, preferredTimescale: asset.duration.timescale)
        let trackTimeRange = CMTimeRangeMake(start: .zero, duration: frame1Time)
        
        guard let videoCompositionTrack = assetComposition.addMutableTrack(withMediaType: .video,
                                                                           preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return
        }
        
        try videoCompositionTrack.insertTimeRange(trackTimeRange, of: videoTrack, at: CMTime.zero)
        
        if let audioTrack = asset.tracks(withMediaType: AVMediaType.audio).first {
            let audioCompositionTrack = assetComposition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                         preferredTrackID: kCMPersistentTrackID_Invalid)
            try audioCompositionTrack?.insertTimeRange(trackTimeRange, of: audioTrack, at: CMTime.zero)
        }
        
        //1. Create the instructions
        let mainInstructions = AVMutableVideoCompositionInstruction()
        mainInstructions.timeRange = CMTimeRangeMake(start: .zero, duration: asset.duration)
        
        //2 add the layer instructions
        let layerInstructions = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack)
        
        let renderSize = CGSize(width: 16 * videoCropView.aspectRatio.width * 18,
                                height: 16 * videoCropView.aspectRatio.height * 18)
        let transform = getTransform(for: videoTrack)
        
        layerInstructions.setTransform(transform, at: CMTime.zero)
        layerInstructions.setOpacity(1.0, at: CMTime.zero)
        mainInstructions.layerInstructions = [layerInstructions]
        
        //3 Create the main composition and add the instructions
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.instructions = [mainInstructions]
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale:     30)
        
        let url = URL(fileURLWithPath: "\(NSTemporaryDirectory())croppedMovie.mp4")
        try? FileManager.default.removeItem(at: url)
        
        let exportSession = AVAssetExportSession(asset: assetComposition, presetName: AVAssetExportPresetHighestQuality)
        exportSession?.outputFileType = AVFileType.mp4
        exportSession?.shouldOptimizeForNetworkUse = true
        exportSession?.videoComposition = videoComposition
        exportSession?.outputURL = url
        exportSession?.exportAsynchronously(completionHandler: {
            
            DispatchQueue.main.async {
                
                if let url1 = exportSession?.outputURL, exportSession?.status == .completed {
                    UISaveVideoAtPathToSavedPhotosAlbum(url1.path, nil, nil, nil)
                    
                    DispatchQueue.main.async {
                        
                        self.hideLoader()
                        let alert = UIAlertController(title: "Video Saved!\n@URL:", message: "\(String(describing: url1))", preferredStyle: UIAlertController.Style.alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        self.present(alert, animated: true, completion: nil)
                        
                    }
                    
                } else {
                    let error = exportSession?.error
                    print("error exporting video \(String(describing: error))")
                }
            }
        })
    }
    
    private func getTransform(for videoTrack: AVAssetTrack) -> CGAffineTransform {
        
        let renderSize = CGSize(width: 16 * videoCropView.aspectRatio.width * 18,
                                height: 16 * videoCropView.aspectRatio.height * 18)
        let cropFrame = videoCropView.getImageCropFrame()
        let renderScale = renderSize.width / cropFrame.width
        let offset = CGPoint(x: -cropFrame.origin.x, y: -cropFrame.origin.y)
        let rotation = atan2(videoTrack.preferredTransform.b, videoTrack.preferredTransform.a)
        
        var rotationOffset = CGPoint(x: 0, y: 0)
        
        if videoTrack.preferredTransform.b == -1.0 {
            rotationOffset.y = videoTrack.naturalSize.width
        } else if videoTrack.preferredTransform.c == -1.0 {
            rotationOffset.x = videoTrack.naturalSize.height
        } else if videoTrack.preferredTransform.a == -1.0 {
            rotationOffset.x = videoTrack.naturalSize.width
            rotationOffset.y = videoTrack.naturalSize.height
        }
        
        var transform = CGAffineTransform.identity
        transform = transform.scaledBy(x: renderScale, y: renderScale)
        transform = transform.translatedBy(x: offset.x + rotationOffset.x, y: offset.y + rotationOffset.y)
        transform = transform.rotated(by: rotation)
        
        print("track size \(videoTrack.naturalSize)")
        print("preferred Transform = \(videoTrack.preferredTransform)")
        print("rotation angle \(rotation)")
        print("rotation offset \(rotationOffset)")
        print("actual Transform = \(transform)")
        
        
        return transform
    }
    
    
}


//loader
extension ViewController{
    func showLoader(){
        
        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.style = UIActivityIndicatorView.Style.medium
        loadingIndicator.startAnimating();
        
        alert.view.addSubview(loadingIndicator)
        self.present(self.alert, animated: true, completion: nil)
    }
    
    func hideLoader(){
        self.alert.dismiss(animated: true, completion: nil)
    }
    
    
}
