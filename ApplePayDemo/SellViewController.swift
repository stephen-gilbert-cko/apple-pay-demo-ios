//
//  SellViewController.swift
//  ApplePayDemo
//
//  Created by Stephen Gilbert on 16/02/2024.
//  Copyright © 2024 Apple. All rights reserved.
//

import UIKit
import PassKit
import MapKit

class SellViewController: UIViewController {

    @IBOutlet var applePayView: UIView!
    @IBOutlet var mapView: MKMapView!
    let paymentHandler = PaymentHandler()

    override func viewDidLoad() {
        super.viewDidLoad()
        let result = PaymentHandler.applePayStatus()
        var button: UIButton?

        if result.canMakePayments {
            button = PKPaymentButton(paymentButtonType: .continue, paymentButtonStyle: .black)
            button?.addTarget(self, action: #selector(SellViewController.payPressed), for: .touchUpInside)
        } else if result.canSetupCards {
            button = PKPaymentButton(paymentButtonType: .setUp, paymentButtonStyle: .black)
            button?.addTarget(self, action: #selector(SellViewController.setupPressed), for: .touchUpInside)
        }

        if let applePayButton = button {
            let constraints = [
                applePayButton.centerXAnchor.constraint(equalTo: applePayView.centerXAnchor),
                applePayButton.centerYAnchor.constraint(equalTo: applePayView.centerYAnchor)
            ]
            applePayButton.translatesAutoresizingMaskIntoConstraints = false
            applePayView.addSubview(applePayButton)
            NSLayoutConstraint.activate(constraints)
        }

        let region = MKCoordinateRegion(center: CLLocationCoordinate2DMake(51.530026, -0.092586), latitudinalMeters: 300, longitudinalMeters: 300)
        mapView.setRegion(region, animated: true)
    }

    @objc func payPressed(sender: AnyObject) {
        paymentHandler.startPayment() { (success) in
            if success {
                self.performSegue(withIdentifier: "Confirmation", sender: self)
            }
        }
    }

    @objc func setupPressed(sender: AnyObject) {
        let passLibrary = PKPassLibrary()
        passLibrary.openPaymentSetup()
    }
}

