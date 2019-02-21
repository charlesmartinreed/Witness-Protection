//
//  ViewController.swift
//  Witness Protection
//
//  Created by Charles Martin Reed on 2/21/19.
//  Copyright © 2019 Charles Martin Reed. All rights reserved.
//

import UIKit
import AVKit
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet weak var videoPreviewView: UIView?
    
    //MARK: AVCapture properties
    var session: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var videoDataOutput: AVCaptureVideoDataOutput?
    var videoDataOutputQueue: DispatchQueue?
    
    var captureDevice: AVCaptureDevice?
    var captureDeviceResolution: CGSize = CGSize()
    
    //ui properties for drawing Vision results
    var rootLayer: CALayer?
    var detectionOverlayLayer: CALayer?
    var detectedFaceRectangleShapeLayer: CAShapeLayer?
    var detectedFaceLandmarksShapeLayer: CAShapeLayer?
    
    //vision request properties
    private var detectionRequests: [VNDetectFaceRectanglesRequest]?
    private var trackingRequests: [VNTrackingRequest]?
    
    lazy var sequenceRequestHandler = VNSequenceRequestHandler() //process request for each frame

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.session = self.setupAVCaptureSession()
        
        //self.prepareVisionRequest()
        
        self.session?.startRunning()
        
    }
    
    //MARK:- Create a capture session for the video
    fileprivate func setupAVCaptureSession() -> AVCaptureSession? {
        let captureSession = AVCaptureSession()

        do {
            let inputDevice = try self.configureFrontCamera(for: captureSession)
            self.configureVideoDataOutput(for: inputDevice.device, resolution: inputDevice.resolution, captureSession: captureSession)
            self.designatePreviewLayer(for: captureSession)
            return captureSession
        } catch let execError as NSError {
            self.presentError(execError)
        } catch {
            self.presentErrorAlert(message: "An unexpected failure has occured")
        }
        
        //before we escape out, we need to dismantle our AVCapture
        self.teardownAVCapture()
        return nil
    }
    
    
    fileprivate func configureFrontCamera(for captureSession: AVCaptureSession) throws -> (device: AVCaptureDevice, resolution: CGSize) {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        
        if let device = deviceDiscoverySession.devices.first {
            if let deviceInput = try? AVCaptureDeviceInput(device: device) {
                if captureSession.canAddInput(deviceInput) {
                    captureSession.addInput(deviceInput)
                }
                
                if let highestResolution = self.highestResolution420Format(for: device) {
                    try device.lockForConfiguration()
                    device.activeFormat = highestResolution.format
                    device.unlockForConfiguration()
                    
                    return (device, highestResolution.resolution)
                }
            }
        }
        
        throw NSError(domain: "ViewController", code: 1, userInfo: nil)
    }
    
    //MARK:- Configuring the dispatchQueue
    fileprivate func configureVideoDataOutput(for inputDevice: AVCaptureDevice, resolution: CGSize, captureSession: AVCaptureSession) {
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        //serial dispatch queue, used for sample buffer delegate AND when a still image is captured. Serial queue because the frames must be delievered in order.
        let videoDataOutputQueue = DispatchQueue(label: "com.charlesmartinreed-sample.Witness_Protection")
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        
        videoDataOutput.connection(with: .video)?.isEnabled = true
        
        if let captureConnection = videoDataOutput.connection(with: .video) {
            if captureConnection.isCameraIntrinsicMatrixDeliverySupported {
                captureConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
        }
    }
    
    //MARK:- Designate a preview layer
    fileprivate func designatePreviewLayer(for captureSession: AVCaptureSession) {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        self.previewLayer = videoPreviewLayer
        
        videoPreviewLayer.name = "CameraPreview"
        videoPreviewLayer.backgroundColor = UIColor.black.cgColor
        videoPreviewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        
        if let previewRootLayer = self.videoPreviewView?.layer {
            self.rootLayer = previewRootLayer
            
            previewRootLayer.masksToBounds = true
            videoPreviewLayer.frame = previewRootLayer.bounds
            previewRootLayer.addSublayer(videoPreviewLayer)
        }
    }
    
    //MARK:- Configure device resolution
    fileprivate func highestResolution420Format(for device: AVCaptureDevice) -> (format: AVCaptureDevice.Format, resolution: CGSize)? {
        var highestResolutionFormat: AVCaptureDevice.Format? = nil
        var highestResolutionDimensions = CMVideoDimensions(width: 0, height: 0)
        
        for format in device.formats {
            let deviceFormat = format as AVCaptureDevice.Format
            
            let deviceFormatDescription = deviceFormat.formatDescription
            if CMFormatDescriptionGetMediaSubType(deviceFormatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
                let candidateDimensions = CMVideoFormatDescriptionGetDimensions(deviceFormatDescription)
                if (highestResolutionFormat == nil) || (candidateDimensions.width > highestResolutionDimensions.width) {
                    highestResolutionFormat = deviceFormat
                    highestResolutionDimensions = candidateDimensions
                }
            }
        }
        
        if highestResolutionFormat != nil {
            let resolution = CGSize(width: CGFloat(highestResolutionDimensions.width), height: CGFloat(highestResolutionDimensions.height))
            return (highestResolutionFormat!, resolution)
        }
        
        return nil
    }
    
    fileprivate func teardownAVCapture() {
        self.videoDataOutput = nil
        self.videoDataOutputQueue = nil
        
        if let previewLayer = self.previewLayer {
            previewLayer.removeFromSuperlayer()
            self.previewLayer = nil
        }
    }
    
    //MARK:- Error presentation methods
    fileprivate func presentErrorAlert(withTitle title: String = "Unexpected Failure", message: String) {
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        self.present(ac, animated: true, completion: nil)
    }
    
    fileprivate func presentError(_ error: NSError) {
        self.presentErrorAlert(withTitle: "Failed with error \(error.code)", message: error.localizedDescription)
    }
    
    //MARK:- Handling/performing vision requests
    fileprivate func prepareVisionRequest() {
        
        //self.trackingRequests = []
        var requests = [VNTrackObjectRequest]()
        
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { (req, err) in
            if err != nil {
                print("FaceDetection error: \(String(describing: err)).")
            }
            
            guard let faceDetectionRequest = req as? VNDetectFaceRectanglesRequest,
                let results = faceDetectionRequest.results as? [VNFaceObservation] else {
                    return
            }
            DispatchQueue.main.async {
                for observation in results {
                    let faceTrackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
                    requests.append(faceTrackingRequest)
                }
                self.trackingRequests = requests
            }
        }
        
        //DETECTION STARTS HERE. FIND A FACE, THE TRACK IT.
        self.detectionRequests = [faceDetectionRequest]
        self.sequenceRequestHandler = VNSequenceRequestHandler() //processes image analysis for each frame
        self.setupVisionDrawingLayers()
    }
    
    //MARK: drawing our layers, post observation
    fileprivate func setupVisionDrawingLayers() {
        let captureDeviceResolution = self.captureDeviceResolution
        let captureDeviceBounds = CGRect(x: 0, y: 0, width: captureDeviceResolution.width, height: captureDeviceResolution.height)
        let captureDeviceBoundsCenterPoint = CGPoint(x: captureDeviceBounds.midX, y: captureDeviceBounds.midY)
        let normalizedCenterPoint = CGPoint(x: 0.5, y: 0.5)
        
        guard let rootLayer = self.rootLayer else {
            self.presentErrorAlert(message: "View was not property intialized")
            return
        }
        
        let overlayLayer = CALayer()
        overlayLayer.name = "DetectionOverlay"
        overlayLayer.masksToBounds = true
        overlayLayer.anchorPoint = normalizedCenterPoint
        overlayLayer.bounds = captureDeviceBounds
        overlayLayer.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        
        let faceRectangleShapeLayer = CAShapeLayer()
        faceRectangleShapeLayer.name = "RectangleOutlineLayer"
        faceRectangleShapeLayer.bounds = captureDeviceBounds
        faceRectangleShapeLayer.anchorPoint = normalizedCenterPoint
        faceRectangleShapeLayer.position = captureDeviceBoundsCenterPoint
        faceRectangleShapeLayer.fillColor = nil
        faceRectangleShapeLayer.strokeColor = UIColor.green.withAlphaComponent(0.7).cgColor
        faceRectangleShapeLayer.lineWidth = 5
        faceRectangleShapeLayer.shadowOpacity = 0.7
        faceRectangleShapeLayer.shadowRadius = 5
        
        let faceLandmarksShapeLayer = CAShapeLayer()
        faceLandmarksShapeLayer.name = "FaceLandmarksLayer"
        faceLandmarksShapeLayer.bounds = captureDeviceBounds
        faceLandmarksShapeLayer.anchorPoint = normalizedCenterPoint
        faceLandmarksShapeLayer.position = captureDeviceBoundsCenterPoint
        faceLandmarksShapeLayer.fillColor = nil
        faceLandmarksShapeLayer.strokeColor = UIColor.yellow.withAlphaComponent(0.7).cgColor
        faceLandmarksShapeLayer.lineWidth = 3
        faceLandmarksShapeLayer.shadowOpacity = 0.7
        faceLandmarksShapeLayer.shadowRadius = 5
        
        overlayLayer.addSublayer(faceRectangleShapeLayer)
        faceRectangleShapeLayer.addSublayer(faceLandmarksShapeLayer)
        rootLayer.addSublayer(overlayLayer)
        
        self.detectionOverlayLayer = overlayLayer
        self.detectedFaceRectangleShapeLayer = faceRectangleShapeLayer
        self.detectedFaceLandmarksShapeLayer = faceLandmarksShapeLayer
        
        self.updateLayerGeometry()
        
    }
    
    fileprivate func updateLayerGeometry() {
        
    }
    
    

}

