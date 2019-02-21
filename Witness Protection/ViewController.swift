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
    
    @IBOutlet weak var videoPreviewView: UIView!
    
    //MARK:- UI properties
    lazy var startTrackingButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(#imageLiteral(resourceName: "Image"), for: .normal)
        
        return button
    }()

    //MARK:- Vision properties
    //because we're streaming video into the vision system, we need a persistent request handler object for the project
    private let visionSequenceHandler = VNSequenceRequestHandler()
    
    //we also need a property to store the observational seed for Vision, which is called renewed with each frame thanks to AVCaptureSession
    private var lastObservation: VNDetectedObjectObservation?
    
    private lazy var previewLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    private lazy var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = AVCaptureSession.Preset.photo
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: frontCamera) else { return session }
        session.addInput(input)
        return session
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.videoPreviewView?.layer.addSublayer(self.previewLayer)
        
        setupUI()
        setupVideoOutput() //sets up the output and starts the capture session
  
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let bounds: CGRect = videoPreviewView.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.bounds = bounds
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }
    
    fileprivate func setupUI() {
        view.addSubview(startTrackingButton)
        
        
        let buttonConstraints: [NSLayoutConstraint] = [
            startTrackingButton.widthAnchor.constraint(equalToConstant: 150),
            startTrackingButton.heightAnchor.constraint(equalToConstant: 150),
            startTrackingButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startTrackingButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: 16)
        ]
        
        NSLayoutConstraint.activate(buttonConstraints)
    }
    
    fileprivate func setupVideoOutput() {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "witness-queue"))
        self.captureSession.addOutput(videoOutput)

        self.captureSession.startRunning()
    }
    
    //MARK:- sample buffer delegte methods
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //get the CVPixelBuffer from CMSampleBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), let lastObservation = self.lastObservation else { return }
        //make sure observations are saved in class property
        
        //create and configure a VNTrackObjectRequest - completion is written below
        let request = VNTrackObjectRequest(detectedObjectObservation: lastObservation, completionHandler: nil)
        
        //favor accuracy over speed
        request.trackingLevel = .accurate
        
        //ask the VNSequenceRequestHandler to perform a request
        do {
            try self.visionSequenceHandler.perform([request], on: pixelBuffer)
        } catch let error as NSError {
            NSLog("Error detecting object: %@", error)
        }
    }

}

