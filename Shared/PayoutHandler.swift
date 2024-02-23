/*
 Abstract:
 A shared class for handling payouts across an app and its related extensions
 */

import UIKit
import PassKit

typealias PayoutCompletionHandler = (Bool) -> Void

@available(iOS 17.0, *)
class PayoutHandler: NSObject {
    
    var paymentController: PKPaymentAuthorizationController?
    var payoutSummaryItems = [PKPaymentSummaryItem]()
    var paymentStatus = PKPaymentAuthorizationStatus.failure
    var completionHandler: PayoutCompletionHandler!
    
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
        .masterCard,
        .visa
    ]
    
    static let supportedCardTypes: PKMerchantCapability = [.debit]
    
    // Filter available cards by supported schemes and types defined above
    class func applePayStatus() -> (supportsDisbursements: Bool, canSetupCards: Bool) {
        return (PKPaymentAuthorizationController.supportsDisbursements(),
                PKPaymentAuthorizationController.supportsDisbursements(using: supportedNetworks, capabilities: supportedCardTypes))
    }
    
    func startPayment(completion: @escaping PayoutCompletionHandler) {
        
        completionHandler = completion
        
        let fundsWithdrawn = PKPaymentSummaryItem(label: "CKO Festival", amount: 9.99)
        let fundsSent = PKDisbursementSummaryItem(label: "Amount received", amount: 9.99)
        payoutSummaryItems = [fundsWithdrawn, fundsSent]
        
        // Build a disbursement request
        let payoutRequest = PKDisbursementRequest()
        payoutRequest.summaryItems = payoutSummaryItems
        payoutRequest.merchantIdentifier = Configuration.Merchant.identifier
        payoutRequest.region = .unitedKingdom
        payoutRequest.currency = Locale.Currency("GBP")
        payoutRequest.supportedNetworks = PayoutHandler.supportedNetworks
        
        // Require recipient details, and limit to payment cards issued in a particular region
        payoutRequest.requiredRecipientContactFields = [.name, .phoneNumber, .emailAddress]
        payoutRequest.supportedRegions = [.unitedKingdom]
        
        // Display the payment sheet
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
    
    // Send temporary token (tok_...) to server to retrieve card metadata: https://www.checkout.com/docs/payments/manage-payments/retrieve-card-metadata#Using_a_token
    // Return eligibility for particular payout scenario
    func getPayoutEligibility(ckoToken: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: Configuration.Server.metadataApiUrl) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["token": ckoToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: .fragmentsAllowed)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                completion(.failure(error ?? NSError(domain: "Data Task Failed", code: 0, userInfo: nil)))
                return
            }
            
            do {
                let jsonResponse = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String: Any]
                
                if let bodyString = jsonResponse?["body"] as? String,
                   let bodyData = bodyString.data(using: .utf8),
                   let body = try JSONSerialization.jsonObject(with: bodyData, options: .fragmentsAllowed) as? [String: Any],
                   let cardPayouts = body["card_payouts"] as? [String: Any],
                   let domesticMoneyTransfer = cardPayouts["domestic_money_transfer"] as? String {
                    completion(.success(domesticMoneyTransfer))
                } else {
                    completion(.failure(NSError(domain: "Error processing response", code: 0, userInfo: nil)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
}

@available(iOS 17.0, *)
extension PayoutHandler: PKPaymentAuthorizationControllerDelegate {
    
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        
        // TODO: Perform basic validation on the provided contact information
        let errors = [Error]()
        let status = PKPaymentAuthorizationStatus.success
        
        // Retrieve encrypted Apple Pay token data
        if !payment.token.paymentData.isEmpty {
            let tokenData = payment.token.paymentData
            let tokenString = String(data: tokenData, encoding: String.Encoding.utf8)!
            print("Apple Pay token data: \(tokenString)\n")
            
            // Send data to Checkout.com to generate temporary token and get payout eligibility
            let decoder = JSONDecoder()
            let decodedTokenData = try! decoder.decode(ApplePayTokenData.self, from: tokenData)
            generateCkoToken(applePayTokenData: decodedTokenData) { result in
                switch result {
                case .success(let token):
                    print("Token: \(token)")
                    self.getPayoutEligibility(ckoToken: token) { result in
                        switch result {
                        case .success(let eligibility):
                            print("Payout eligibility: \(eligibility)")
                        case .failure(let error):
                            print("Error: \(error)")
                        }
                    }
                case .failure(let error):
                    print("Error: \(error)")
                }
            }
            // TODO: Send temporary token (tok_...) to server to request payout
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
