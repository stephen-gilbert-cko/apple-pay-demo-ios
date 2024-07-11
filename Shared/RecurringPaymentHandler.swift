//
//  RecurringPaymentHandler.swift
//  ApplePayDemo
//
//  Created by Stephen Gilbert on 09/07/2024.
//  Copyright © 2024 Apple. All rights reserved.
//

import UIKit
import PassKit

typealias RecurringPaymentCompletionHandler = (Bool) -> Void

@available(iOS 16.0, *)
class RecurringPaymentHandler: NSObject {
    
    var paymentController: PKPaymentAuthorizationController?
    var paymentSummaryItems = [PKPaymentSummaryItem]()
    var paymentStatus = PKPaymentAuthorizationStatus.failure
    var completionHandler: PaymentCompletionHandler!
    
    struct ApplePayTokenData: Codable {
        let version: String
        let data: String
        let signature: String
        let header: ApplePayTokenDataHeader
    }
    
    struct ApplePayTokenDataHeader: Codable {
        let ephemeralPublicKey: String
        let publicKeyHash: String
        let transactionId: String
    }
    
    static let supportedNetworks: [PKPaymentNetwork] = [
        .amex,
        .discover,
        .masterCard,
        .visa
    ]
    
    // Filter available cards by supported schemes defined above
    class func applePayStatus() -> (canMakePayments: Bool, canSetupCards: Bool) {
        return (PKPaymentAuthorizationController.canMakePayments(),
                PKPaymentAuthorizationController.canMakePayments(usingNetworks: supportedNetworks))
    }
    
    func startPayment(completion: @escaping PaymentCompletionHandler) {
        
        completionHandler = completion
        
        //Specify the amount and billing periods
        let regularBilling = PKRecurringPaymentSummaryItem(label: "Membership", amount: 20)
        let trialBilling = PKRecurringPaymentSummaryItem(label: "Trial Membership", amount: 10)
        let trialEndDate = Calendar.current.date(byAdding: .month, value: 1, to: Date.now)
        trialBilling.endDate = trialEndDate
        regularBilling.startDate = trialEndDate
        
        // Build a recurring payment request
        let recurringPaymentRequest = PKRecurringPaymentRequest(
            paymentDescription: "VIP Membership",
            regularBilling: regularBilling,
            managementURL: URL(string: "https://www.example.com/managementURL")!
        )
        recurringPaymentRequest.trialBilling = trialBilling
        
        recurringPaymentRequest.billingAgreement = """
        50% off for the first month. You will be charged £20 every month after that until you cancel. \
        You may cancel at any time to avoid future charges. To cancel, go to your Account and click \
        Cancel Membership.
        """
        
        recurringPaymentRequest.tokenNotificationURL = URL(
            string: "https://www.example.com/tokenNotificationURL"
        )
        
        // Update the payment request
        let paymentRequest = PKPaymentRequest()
        paymentRequest.merchantIdentifier = Configuration.Merchant.identifier
        paymentRequest.merchantCapabilities = .capability3DS
        paymentRequest.countryCode = "GB"
        paymentRequest.currencyCode = "GBP"
        paymentRequest.supportedNetworks = PaymentHandler.supportedNetworks
        paymentRequest.recurringPaymentRequest = recurringPaymentRequest
        
        // Include in the summary items
        let total = PKRecurringPaymentSummaryItem(label: "VIP", amount: 10)
        total.endDate = trialEndDate
        paymentRequest.paymentSummaryItems = [trialBilling, regularBilling, total]
        
        // Display the payment sheet
        paymentController = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
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
    
    // Send Apple Pay token data to Checkout.com for decryption
    // Return temporary token (tok_...) for further processing
    func generateCkoToken(applePayTokenData: ApplePayTokenData, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.sandbox.checkout.com/tokens") else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Configuration.CheckoutDotCom.publicKey, forHTTPHeaderField: "Authorization")
        
        do {
            let headerData = try JSONEncoder().encode(applePayTokenData.header)
            
            let body: [String: Any] = [
                "type": "applepay",
                "token_data": [
                    "version": applePayTokenData.version,
                    "data": applePayTokenData.data,
                    "signature": applePayTokenData.signature,
                    "header": try JSONSerialization.jsonObject(with: headerData, options: [])
                ]
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            URLSession.shared.dataTask(with: request) { data, _, error in
                guard let data = data, error == nil else {
                    completion(.failure(error ?? NSError(domain: "Data Task Failed", code: 0, userInfo: nil)))
                    return
                }
                
                do {
                    if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let token = jsonResponse["token"] as? String {
                        completion(.success(token))
                    } else {
                        completion(.failure(NSError(domain: "Token not found in response", code: 0, userInfo: nil)))
                    }
                } catch {
                    completion(.failure(error))
                }
            }.resume()
            
        } catch {
            completion(.failure(NSError(domain: "Header Encoding Failed", code: 0, userInfo: nil)))
        }
    }
}

@available(iOS 16.0, *)
extension RecurringPaymentHandler: PKPaymentAuthorizationControllerDelegate {
    
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        
        var errors = [Error]()
        var status = PKPaymentAuthorizationStatus.success
        
        // Retrieve encrypted Apple Pay token data
        if !payment.token.paymentData.isEmpty {
            let tokenData = payment.token.paymentData
            let tokenString = String(data: tokenData, encoding: String.Encoding.utf8)!
            print("Apple Pay token data: \(tokenString)\n")
            
            // Customer-facing display name for card
            let displayName = payment.token.paymentMethod.displayName ?? "No display name"
            print("Card display name: \(displayName)\n")
            
            // Send data to Checkout.com to generate temporary token
            let decoder = JSONDecoder()
            let decodedTokenData = try! decoder.decode(ApplePayTokenData.self, from: tokenData)
            generateCkoToken(applePayTokenData: decodedTokenData) { result in
                switch result {
                case .success(let token):
                    print("Token: \(token)")
                case .failure(let error):
                    print("Error: \(error)")
                }
            }
            // TODO: Send temporary token (tok_...) to server to request payment
            // Once processed, return an appropriate status in the completion handler (success, failure etc.)
        }
        
        self.paymentStatus = status
        completion(PKPaymentAuthorizationResult(status: status, errors: errors))
    }
    
    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss {
            // The payment sheet doesn't automatically dismiss once it has finished; dismiss the payment sheet
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

