/*
 Abstract:
 A shared class for handling payments across an app and its related extensions
 */

import UIKit
import PassKit

typealias PaymentCompletionHandler = (Bool) -> Void

class PaymentHandler: NSObject {
    
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
    
    // Define shipping methods
    func shippingMethodCalculator() -> [PKShippingMethod] {
        
        // Calculate delivery dates
        let today = Date()
        let calendar = Calendar.current
        let shippingStart = calendar.date(byAdding: .day, value: 3, to: today)!
        let shippingEnd = calendar.date(byAdding: .day, value: 5, to: today)!
        
        let startComponents = calendar.dateComponents([.calendar, .year, .month, .day], from: shippingStart)
        let endComponents = calendar.dateComponents([.calendar, .year, .month, .day], from: shippingEnd)
        
        let shippingDelivery = PKShippingMethod(label: "Delivery", amount: NSDecimalNumber(string: "0.00"))
        shippingDelivery.dateComponentsRange = PKDateComponentsRange(start: startComponents, end: endComponents)
        shippingDelivery.detail = "Ticket sent to your address"
        shippingDelivery.identifier = "DELIVERY"
        
        let shippingCollection = PKShippingMethod(label: "Collection", amount: NSDecimalNumber(string: "0.00"))
        shippingCollection.detail = "Collect ticket at festival"
        shippingCollection.identifier = "COLLECTION"
        
        return [shippingDelivery, shippingCollection]
    }
    
    func startPayment(completion: @escaping PaymentCompletionHandler) {
        
        completionHandler = completion
        
        let ticket = PKPaymentSummaryItem(label: "Festival Entry", amount: NSDecimalNumber(string: "9.99"), type: .final)
        let tax = PKPaymentSummaryItem(label: "Tax", amount: NSDecimalNumber(string: "1.00"), type: .final)
        let total = PKPaymentSummaryItem(label: "Total", amount: NSDecimalNumber(string: "10.99"), type: .final)
        paymentSummaryItems = [ticket, tax, total]
        
        // Build a payment request
        let paymentRequest = PKPaymentRequest()
        paymentRequest.paymentSummaryItems = paymentSummaryItems
        paymentRequest.merchantIdentifier = Configuration.Merchant.identifier
        paymentRequest.merchantCapabilities = .capability3DS
        paymentRequest.countryCode = "GB"
        paymentRequest.currencyCode = "GBP"
        paymentRequest.supportedNetworks = PaymentHandler.supportedNetworks
        paymentRequest.shippingType = .delivery
        paymentRequest.shippingMethods = shippingMethodCalculator()
        paymentRequest.requiredShippingContactFields = [.name, .postalAddress]
        paymentRequest.supportsCouponCode = true
        
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

extension PaymentHandler: PKPaymentAuthorizationControllerDelegate {
    
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        
        // Perform basic validation on the provided contact information
        var errors = [Error]()
        var status = PKPaymentAuthorizationStatus.success
        if payment.shippingContact?.postalAddress?.isoCountryCode != "GB" {
            let pickupError = PKPaymentRequest.paymentShippingAddressUnserviceableError(withLocalizedDescription: "Please provide a UK address")
            let countryError = PKPaymentRequest.paymentShippingAddressInvalidError(withKey: CNPostalAddressCountryKey, localizedDescription: "Invalid country")
            errors.append(pickupError)
            errors.append(countryError)
            status = .failure
        } else {
            // Retrieve encrypted Apple Pay token data
            if !payment.token.paymentData.isEmpty {
                let tokenData = payment.token.paymentData
                let tokenString = String(data: tokenData, encoding: String.Encoding.utf8)!
                print("Apple Pay token data: \(tokenString)")
                
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
    
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController,
                                        didChangeCouponCode couponCode: String,
                                        handler completion: @escaping (PKPaymentRequestCouponCodeUpdate) -> Void) {
        
        // Apply a discount when the user enters a valid coupon code
        func applyDiscount(items: [PKPaymentSummaryItem]) -> [PKPaymentSummaryItem] {
            let tickets = items.first!
            let couponDiscountItem = PKPaymentSummaryItem(label: "Coupon Code Applied", amount: NSDecimalNumber(string: "-2.00"))
            let updatedTax = PKPaymentSummaryItem(label: "Tax", amount: NSDecimalNumber(string: "0.80"), type: .final)
            let updatedTotal = PKPaymentSummaryItem(label: "Total", amount: NSDecimalNumber(string: "8.80"), type: .final)
            let discountedItems = [tickets, couponDiscountItem, updatedTax, updatedTotal]
            return discountedItems
        }
        
        if couponCode.uppercased() == "FESTIVAL" {
            // If the coupon code is valid, update the summary items
            let couponCodeSummaryItems = applyDiscount(items: paymentSummaryItems)
            completion(PKPaymentRequestCouponCodeUpdate(paymentSummaryItems: applyDiscount(items: couponCodeSummaryItems)))
            return
        } else if couponCode.isEmpty {
            // If the user doesn't enter a code, return the current payment summary items
            completion(PKPaymentRequestCouponCodeUpdate(paymentSummaryItems: paymentSummaryItems))
            return
        } else {
            // If the user enters a code, but it's not valid, display an error
            let couponError = PKPaymentRequest.paymentCouponCodeInvalidError(localizedDescription: "Coupon code is not valid.")
            completion(PKPaymentRequestCouponCodeUpdate(errors: [couponError], paymentSummaryItems: paymentSummaryItems, shippingMethods: shippingMethodCalculator()))
            return
        }
    }
}
