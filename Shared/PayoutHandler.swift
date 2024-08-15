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
    
    let paymentAmount:NSDecimalNumber = 9.99;
    
    struct ApplePayTokenData: Codable {
        let version: String
        let data: String
        let signature: String
        let header: ApplePayTokenDataHeader
    }
    
    struct ApplePayTokenDataHeader: Codable {
        let ephemeralPublicKey: String?
        let wrappedKey: String?
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
        
        let fundsWithdrawn = PKPaymentSummaryItem(label: "CKO Festival", amount: paymentAmount)
        let fundsSent = PKDisbursementSummaryItem(label: "Amount received", amount: paymentAmount)
        payoutSummaryItems = [fundsWithdrawn, fundsSent]
        
        // Build a disbursement request
        let payoutRequest = PKDisbursementRequest()
        payoutRequest.summaryItems = payoutSummaryItems
        payoutRequest.merchantIdentifier = Configuration.Merchant.identifier
        payoutRequest.region = .unitedKingdom
        payoutRequest.currency = Locale.Currency("GBP")
        payoutRequest.supportedNetworks = PayoutHandler.supportedNetworks
        payoutRequest.merchantCapabilities = .threeDSecure
        
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
    func getPayoutEligibility(ckoToken: String, payoutScenario: String, completion: @escaping (Result<String, Error>) -> Void) {
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
                   let eligibility = cardPayouts[payoutScenario] as? String {
                    completion(.success(eligibility))
                } else {
                    completion(.failure(NSError(domain: "Error processing response", code: 0, userInfo: nil)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // Call server to retrieve balance information for a given currency account: https://www.checkout.com/docs/payments/request-payouts/card-payouts/request-an-apple-pay-card-payout#Check_currency_account_balance
    // Return available balance
    func getAvailableBalance(currencyAccountId: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: Configuration.Server.balancesApiUrl) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                let errorMessage = error?.localizedDescription ?? "Unknown error"
                completion(.failure(NSError(domain: "Data Task Failed", code: 0, userInfo: ["error": errorMessage])))
                return
            }
            
            do {
                guard let jsonResponse = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? [String: Any] else {
                    completion(.failure(NSError(domain: "Error converting JSON data to dictionary", code: 0, userInfo: nil)))
                    return
                }
                
                guard let bodyString = jsonResponse["body"] as? String,
                      let bodyData = bodyString.data(using: .utf8),
                      let body = try JSONSerialization.jsonObject(with: bodyData, options: .fragmentsAllowed) as? [String: Any],
                      let dictionary = body["data"] as? [[String: Any]] else {
                    completion(.failure(NSError(domain: "Error processing response", code: 0, userInfo: nil)))
                    return
                }
                
                // Loop through the data array to find the matching currency_account_id
                for accountData in dictionary {
                    guard let accountId = accountData["currency_account_id"] as? String else {
                        completion(.failure(NSError(domain: "Missing or invalid 'currency_account_id' in response", code: 0, userInfo: nil)))
                        continue
                    }
                    
                    if accountId == currencyAccountId {
                        if let balances = accountData["balances"] as? [String: Any],
                           let availableBalance = balances["available"] as? Int {
                            completion(.success("\(availableBalance)"))
                            return
                        } else {
                            completion(.failure(NSError(domain: "Missing or invalid 'available' balance for currency account", code: 0, userInfo: nil)))
                        }
                    }
                }
                // If the loop completes without finding a match
                completion(.failure(NSError(domain: "No account found with currency_account_id: \(currencyAccountId)", code: 0, userInfo: nil)))
                
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func printPaymentMethodJSON(payment: PKPayment) {
        let paymentMethod = payment.token.paymentMethod

        // Create a struct to represent the payment method details
        struct PaymentMethodDetails: Codable {
            let displayName: String?
            let network: String?
            let type: String
        }

        // Map PKPaymentMethod properties to the struct
        let paymentMethodDetails = PaymentMethodDetails(
            displayName: paymentMethod.displayName,
            network: paymentMethod.network?.rawValue,
            type: paymentMethod.type.payoutCardType
        )

        // Encode the struct to JSON
        if let jsonData = try? JSONEncoder().encode(paymentMethodDetails) {
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("Payment method data: \(jsonString)\n")
            }
        } else {
            print("Failed to encode payment method to JSON")
        }
    }
}

extension PKPaymentMethodType {
    var payoutCardType: String {
        switch self {
        case .unknown:
            return "unknown"
        case .debit:
            return "debit"
        case .credit:
            return "credit"
        case .prepaid:
            return "prepaid"
        case .store:
            return "store"
        case .eMoney:
            return "eMoney"
        @unknown default:
            return "unknown"
        }
    }
}

@available(iOS 17.0, *)
extension PayoutHandler: PKPaymentAuthorizationControllerDelegate {
    
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        
        var errors = [Error]()
        var status = PKPaymentAuthorizationStatus.success
        
        // Perform basic validation on the provided first/last name
        var contactName = payment.billingContact?.name?.givenName
        if let familyName = payment.billingContact?.name?.familyName {
            contactName = "\(contactName ?? "") \(familyName)"
        }
        let isValidName: Bool
        if let contactName = contactName {
            isValidName = contactName.range(of: #"[a-zA-Z '-]+"#, options: .regularExpression) == contactName.startIndex..<contactName.endIndex
        } else {
            isValidName = false
        }
        
        print("Recipient name valid?: \(isValidName)\n")
        if !isValidName {
            // Present error if the first/last name are invalid
            let eligibilityError = PKDisbursementRequest.disbursementContactInvalidError(withContactField: .name, localizedDescription: "Recipient name not valid")
            errors.append(eligibilityError)
            status = .failure
        }
        
        // Retrieve encrypted Apple Pay token data
        if !payment.token.paymentData.isEmpty {
            let tokenData = payment.token.paymentData
            let tokenString = String(data: tokenData, encoding: String.Encoding.utf8)!
            print("\nApple Pay token data: \(tokenString)\n")
            
            // Customer-facing display name for card
            let displayName = payment.token.paymentMethod.displayName ?? "No display name"
            print("Card display name: \(displayName)\n")
            
            printPaymentMethodJSON(payment: payment)
            
            // Send data to Checkout.com to generate temporary token (tok_...), check payout eligibility and funds availability
            let decoder = JSONDecoder()
            let decodedTokenData = try! decoder.decode(ApplePayTokenData.self, from: tokenData)
            generateCkoToken(applePayTokenData: decodedTokenData) { result in
                switch result {
                case .success(let token):
                    print("Token: \(token)\n")
                    
                    self.getPayoutEligibility(ckoToken: token, payoutScenario: "domestic_money_transfer") { result in
                        switch result {
                        case .success(let eligibility):
                            print("Payout eligibility: \(eligibility)\n")
                            
                            // Check available balance if card is eligible or eligibilty is unknown
                            let eligiblePossibilities = ["fast_funds", "standard", "unknown"]
                            if (eligiblePossibilities.contains(eligibility)) {
                                self.getAvailableBalance(currencyAccountId: Configuration.CheckoutDotCom.currencyAccountId) {  result in
                                    switch result {
                                    case .success(let availableBalance):
                                        print("Available balance: \(availableBalance)\n")
                                        
                                        // If available balance is > payment amount then make a payout request
                                        let availableBalanceDecimal = NSDecimalNumber(string: availableBalance)
                                        if availableBalanceDecimal.compare(self.paymentAmount) == .orderedDescending || availableBalanceDecimal.compare(self.paymentAmount) == .orderedSame {
                                            print("Send Payout!")
                                            // TODO: Send temporary token to server to request payout
                                            // Once processed, return an appropriate status in the completion handler (success, failure etc.)
                                            status = .success
                                        } else {
                                            print("Insufficient balance")
                                            status = .failure
                                        }
                                        
                                    case .failure(let error):
                                        print("Error: \(error)")
                                        status = .failure
                                    }
                                }
                                
                            } else {
                                // Present error if the card is ineligible
                                let eligibilityError = PKDisbursementRequest.disbursementCardUnsupportedError()
                                errors.append(eligibilityError)
                                status = .failure
                            }
                            
                        case .failure(let error):
                            print("Error: \(error)")
                            status = .failure
                        }
                    }
                case .failure(let error):
                    print("Error: \(error)")
                    status = .failure
                }
            }
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
