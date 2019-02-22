//
//  ViewController.swift
//  Witness Protection
//
//  Created by Charles Martin Reed on 2/21/19.
//  Copyright © 2019 Charles Martin Reed. All rights reserved.
//

import Foundation
import UIKit
import AVKit
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet weak var videoPreviewView: UIView!
    
    //MARK:- UI properties
    lazy var trackingButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(#imageLiteral(resourceName: "Image"), for: .normal)
        button.isHidden = true
        
        return button
    }()
    
    lazy var recordButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = .green
        button.layer.cornerRadius = 25
        
        button.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        return button
    }()
    
    let shapeLayer = CAShapeLayer()
    
    //MARK:- Vision properties
    let faceDetection = VNDetectFaceRectanglesRequest()
    let faceLandmarks = VNDetectFaceLandmarksRequest()
    let faceLandmarksDetectionRequest = VNSequenceRequestHandler()
    let faceDetectionSequenceRequest = VNSequenceRequestHandler()
    var boundingBoxExists = false

    //MARK:- AVKit properties
    var session: AVCaptureSession?
    var userIsRecording: Bool = false {
        didSet {
            if userIsRecording {
                recordButton.backgroundColor = .red
            } else {
                recordButton.backgroundColor = .green
            }
        }
    }
    
    private lazy var previewLayer: AVCaptureVideoPreviewLayer? = {
        guard let session = self.session else { return nil }
        
        var previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        
        return previewLayer
    }()
    
    var frontCamera: AVCaptureDevice? = {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        prepareSession()
        session?.startRunning()
  
    }
    
    override func viewDidLayoutSubviews() {
        
        super.viewDidLayoutSubviews()
        previewLayer?.frame = videoPreviewView.frame
        shapeLayer.frame = videoPreviewView.frame
        //previewLayer?.mask = shapeLayer.mask
        previewLayer?.opacity = 0
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let previewLayer = previewLayer else { return }
        
        videoPreviewView.layer.addSublayer(previewLayer)
        
        //shapeLayer.strokeColor = UIColor.red.cgColor
        //shapeLayer.lineWidth = 2.0
        
        //coord system is flipped for Vision
        shapeLayer.setAffineTransform(CGAffineTransform(scaleX: -1, y: -1))
        
        videoPreviewView.layer.addSublayer(shapeLayer)
    }
    
    fileprivate func setupUI() {
        view.addSubview(trackingButton)
        view.addSubview(recordButton)
        
        let trackingButtonConstraints: [NSLayoutConstraint] = [
            trackingButton.widthAnchor.constraint(equalToConstant: 150),
            trackingButton.heightAnchor.constraint(equalToConstant: 150),
            trackingButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            trackingButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 16)
        ]
        
        let recordButtonConstriants: [NSLayoutConstraint] = [
            recordButton.widthAnchor.constraint(equalToConstant: 50),
            recordButton.heightAnchor.constraint(equalToConstant: 50),
            recordButton.topAnchor.constraint(equalTo: videoPreviewView.safeAreaLayoutGuide.topAnchor, constant: 16),
            recordButton.trailingAnchor.constraint(equalTo: videoPreviewView.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ]
        
        NSLayoutConstraint.activate(trackingButtonConstraints)
        NSLayoutConstraint.activate(recordButtonConstriants)
        
    }
    
    //MARK:- Record button methods
    @objc fileprivate func recordButtonTapped() {
        animateRecordButton()
        
        if !userIsRecording {
            beginVideoRecording()
        } else {
            finishVideoRecording()
        }
        
        
    }
    
    fileprivate func animateRecordButton() {
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        
        if !userIsRecording {
            anim.fromValue = UIColor.green.cgColor
            anim.toValue = UIColor.red.cgColor
        } else {
            anim.fromValue = UIColor.red.cgColor
            anim.toValue = UIColor.green.cgColor
        }
        
        anim.duration = 0.5
        recordButton.layer.add(anim, forKey: "backgroundColor")
        
        userIsRecording.toggle()
    }
    
    //MARK:- Recording video
    fileprivate func beginVideoRecording() {
        
    }
    
    fileprivate func finishVideoRecording() {
        
    }
    
    //MARK:- Add input/output devices to capture session
    fileprivate func prepareSession() {
        session = AVCaptureSession()
        guard let session = session, let captureDevice = frontCamera else { return }
        
        do {
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
            session.beginConfiguration()
            
            if session.canAddInput(deviceInput) {
                session.addInput(deviceInput)
            }
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey) : Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            output.alwaysDiscardsLateVideoFrames = true
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            session.commitConfiguration()
            let queue = DispatchQueue(label: "witness-output")
            output.setSampleBufferDelegate(self, queue: queue)
        } catch let error as NSError {
            NSLog("Could not prepare session: %@", error)
        }
        
    }

    
    //MARK:- sample buffer delegte methods
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let attachments = CMCopyDictionaryOfAttachments(allocator: kCFAllocatorDefault, target: sampleBuffer, attachmentMode: kCMAttachmentMode_ShouldPropagate)
        let ciImage = CIImage(cvImageBuffer: pixelBuffer!, options: attachments as! [CIImageOption : Any]?)
        
        //leftMirrored for front cam
        let ciImageWithOrientation = ciImage.oriented(forExifOrientation: Int32(UIImage.Orientation.leftMirrored.rawValue))
        detectFace(on: ciImageWithOrientation)
       
    }

}

extension ViewController {
    func detectFace(on image: CIImage) {
        try? faceDetectionSequenceRequest.perform([faceDetection], on: image)
        if let results = faceDetection.results as? [VNFaceObservation] {
            if !results.isEmpty {
                faceLandmarks.inputFaceObservations = results
                detectLandmarks(on: image)
                
                DispatchQueue.main.async {
                    self.shapeLayer.sublayers?.removeAll()
                    
                }
            }
        }
    }
    
    func detectLandmarks(on image: CIImage) {
        try? faceLandmarksDetectionRequest.perform([faceLandmarks], on: image)
        if let landmarkResults = faceLandmarks.results as? [VNFaceObservation] {
            for observation in landmarkResults {
                DispatchQueue.main.async {
                    //the face itself
                    if let boundingBox = self.faceLandmarks.inputFaceObservations?.first?.boundingBox {
                        let faceBoundingBox = boundingBox.scaled(to: self.view.bounds.size)
                        
                        let faceContour = observation.landmarks?.faceContour
                        self.convertPointsForFace(faceContour, faceBoundingBox)

                        let leftEye = observation.landmarks?.leftEye
                        self.convertPointsForFace(leftEye, faceBoundingBox)

                        let rightEye = observation.landmarks?.rightEye
                        self.convertPointsForFace(rightEye, faceBoundingBox)

                        let nose = observation.landmarks?.nose
                        self.convertPointsForFace(nose, faceBoundingBox)

                        let lips = observation.landmarks?.innerLips
                        self.convertPointsForFace(lips, faceBoundingBox)

                        let leftEyebrow = observation.landmarks?.leftEyebrow
                        self.convertPointsForFace(leftEyebrow, faceBoundingBox)

                        let rightEyebrow = observation.landmarks?.rightEyebrow
                        self.convertPointsForFace(rightEyebrow, faceBoundingBox)

                        let noseCrest = observation.landmarks?.noseCrest
                        self.convertPointsForFace(noseCrest, faceBoundingBox)

                        let outerLips = observation.landmarks?.outerLips
                        self.convertPointsForFace(outerLips, faceBoundingBox)
                        
                    }
                    
                }
            }
        }
    }
    
    func convertPointsForFace(_ landmark: VNFaceLandmarkRegion2D?, _ boundingBox: CGRect) {
        if let points = landmark?.normalizedPoints, let count = landmark?.pointCount {
            let convertedPoints = convert(points, with: count)
            
            let faceLandmarkPoints = convertedPoints.map { (point: (x: CGFloat, y: CGFloat)) -> (x: CGFloat, y: CGFloat) in
                let pointX = point.x * boundingBox.width + boundingBox.origin.x
                let pointY = point.y * boundingBox.height + boundingBox.origin.y
                
                return (x: pointX, y: pointY)
            }
            
            DispatchQueue.main.async {

                self.draw(points: faceLandmarkPoints)
            }
            
        }
    }
    
    func draw(points: [(x: CGFloat, y: CGFloat)]) {
        let newLayer = CAShapeLayer()
        newLayer.strokeColor = UIColor.black.cgColor
        newLayer.lineWidth = 3.0
        
        let path = UIBezierPath()
        path.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for i in 0..<points.count - 1 {
            let point = CGPoint(x: points[i].x, y: points[i].y)
            path.addLine(to: point)
            path.move(to: point)
            
        }
        
        path.addLine(to: CGPoint(x: points[0].x, y: points[0].y))
        newLayer.path = path.cgPath
        
        shapeLayer.addSublayer(newLayer)
        
    }
    
    func convert(_ points: [CGPoint], with count: Int) -> [(x: CGFloat, y: CGFloat)] {
        var convertedPoints = [(x: CGFloat, y: CGFloat)]()
        for i in 0..<count {
            convertedPoints.append((CGFloat(points[i].x), CGFloat(points[i].y)))
        }
        
        return convertedPoints
    }
    
    private func faceFrame(from boundingBox: CGRect) -> CGRect {
        let origin = CGPoint(x: boundingBox.minX * videoPreviewView.bounds.width, y: (1 - boundingBox.maxY) * videoPreviewView.bounds.height)
        let size = CGSize(width: boundingBox.width * videoPreviewView.bounds.width, height: boundingBox.height * videoPreviewView.bounds.height)
        
        return CGRect(origin: origin, size: size)
    }
    
}

extension CGRect {
    func scaled(to size: CGSize) -> CGRect {
        return CGRect(x: self.origin.x * size.width, y: self.origin.y * size.height, width: self.size.width * size.width, height: self.size.height * size.height)
    }
}


