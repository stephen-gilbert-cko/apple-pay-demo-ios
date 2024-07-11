/*
 Abstract:
 Handles merchant-specific configuration logic
 */

import Foundation

public class Configuration {
    private struct MainBundle {
        static var prefix: String = {
            guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AAPLOfferingApplePayBundlePrefix") as? String else {
                return ""
            }
            return prefix
        }()
    }
    
    struct Merchant {
        static let identifier = "<YOUR_APPLE_MERCHANT_ID>" // e.g. merchant.checkout.applepaydemo
    }
    
    struct CheckoutDotCom {
        static let publicKey = "<YOUR_CKO_PUBLIC_API_KEY>" // pk_...
        static let currencyAccountId = "<YOUR_CKO_CURRENCY_ACCOUNT_ID>" // ca_...
    }
    
    struct Server {
        static let metadataApiUrl = "<YOUR_SERVER_API_URL>"
        static let balancesApiUrl = "<YOUR_SERVER_API_URL>"
    }
}
