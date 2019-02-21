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
    
    //MARK:- UI elements
    lazy var startTrackingButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(#imageLiteral(resourceName: "Image"), for: .normal)
        
        return button
    }()


    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
  
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
   
    

}

