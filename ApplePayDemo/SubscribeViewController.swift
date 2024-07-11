/*
 Abstract:
 "VIP" tab view controller
 */

import UIKit
import PassKit
import MapKit

@available(iOS 16.0, *)
class SubscribeViewController: UIViewController {
    
    @IBOutlet weak var applePayView: UIView!
    @IBOutlet weak var mapView: MKMapView!
    let paymentHandler = RecurringPaymentHandler()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let result = RecurringPaymentHandler.applePayStatus()
        var button: UIButton?
        
        if result.canMakePayments {
            button = PKPaymentButton(paymentButtonType: .subscribe, paymentButtonStyle: .black)
            button?.addTarget(self, action: #selector(SubscribeViewController.payPressed), for: .touchUpInside)
        } else if result.canSetupCards {
            button = PKPaymentButton(paymentButtonType: .setUp, paymentButtonStyle: .black)
            button?.addTarget(self, action: #selector(SubscribeViewController.setupPressed), for: .touchUpInside)
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
