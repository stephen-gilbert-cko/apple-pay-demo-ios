//
//  PayoutHandler.swift
//  ApplePayDemo
//
//  Created by Stephen Gilbert on 16/02/2024.
//  Copyright © 2024 Apple. All rights reserved.
//

import UIKit
import PassKit

typealias PayoutCompletionHandler = (Bool) -> Void

@available(iOS 17.0, *)
class PayoutHandler: NSObject {
    
    var paymentController: PKPaymentAuthorizationController?
    var payoutSummaryItems = [PKPaymentSummaryItem]()
    var paymentStatus = PKPaymentAuthorizationStatus.failure
    var completionHandler: PayoutCompletionHandler!
    
    static let supportedNetworks: [PKPaymentNetwork] = [
        .masterCard,
        .visa
    ]
    
    static let supportedCardTypes: PKMerchantCapability = [.debit]
    
    class func applePayStatus() -> (supportsDisbursements: Bool, canSetupCards: Bool) {
            return (PKPaymentAuthorizationController.supportsDisbursements(),
                    PKPaymentAuthorizationController.supportsDisbursements(using: supportedNetworks, capabilities: supportedCardTypes))
    }
    
    func startPayment(completion: @escaping PayoutCompletionHandler) {
        
        completionHandler = completion
        
        let fundsWithdrawn = PKPaymentSummaryItem(label: "CKO Festival", amount: 9.99)
        let fundsSent = PKDisbursementSummaryItem(label: "Amount received", amount: 9.99)
        payoutSummaryItems = [fundsWithdrawn, fundsSent]
        
        // Create a disbursement request.
            let payoutRequest = PKDisbursementRequest()
            payoutRequest.summaryItems = payoutSummaryItems
            payoutRequest.merchantIdentifier = Configuration.Merchant.identifier
            payoutRequest.region = .unitedKingdom
            payoutRequest.currency = Locale.Currency("GBP")
            payoutRequest.supportedNetworks = PayoutHandler.supportedNetworks
            
            // Require recipient details, and limit to payment cards issued in a particular region.
            payoutRequest.requiredRecipientContactFields = [.name, .phoneNumber, .emailAddress]
            payoutRequest.supportedRegions = [.unitedKingdom]
            
            // Display the payment request.
            paymentController = PKPaymentAuthorizationController(disbursementRequest: payoutRequest)
            paymentController?.delegate = self
            paymentController?.present(completion: { (presented: Bool) in
                if presented {
                    debugPrint("Presented payment controller")
                } else {
                    debugPrint("Failed to present payment controller")
                    self.completionHandler(false)
                }
            })
    }
}

// Set up PKPaymentAuthorizationControllerDelegate conformance.

@available(iOS 17.0, *)
extension PayoutHandler: PKPaymentAuthorizationControllerDelegate {
    
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        
        // Perform basic validation on the provided contact information.
        let errors = [Error]()
        let status = PKPaymentAuthorizationStatus.success
        
        // Send the payment token to your server or payment provider to process here.
        // Once processed, return an appropriate status in the completion handler (success, failure, and so on).
        
        if !payment.token.paymentData.isEmpty {
            let applePayTokenData = String(data: payment.token.paymentData, encoding: String.Encoding.utf8)!
            print("Apple Pay token data: \(applePayTokenData)")
            
            // TODO: processToken(payment.token.paymentData)
        }
        
        
        self.paymentStatus = status
        completion(PKPaymentAuthorizationResult(status: status, errors: errors))
    }
    
    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss {
            // The payment sheet doesn't automatically dismiss once it has finished. Dismiss the payment sheet.
            DispatchQueue.main.async {
                if self.paymentStatus == .success {
                    self.completionHandler!(true)
                } else {
                    self.completionHandler!(false)
                }
            }
        }
    }
}

