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
//        static let identifier = "<YOUR_APPLE_MERCHANT_ID>"
        static let identifier = "merchant.checkout.applepaydemo"
    }
    
    struct CheckoutDotCom {
//        static let publicKey = "<YOUR_CKO_PUBLIC_API_KEY>"
        static let publicKey = "pk_sbox_svm7ctgfxkhbfthi4blfb765nyq"
    }
    
    struct Server {
//        static let metadataApiUrl = "<YOUR_SERVER_API_URL>"
//        static let balancesApiUrl = "<YOUR_SERVER_API_URL>"
        static let metadataApiUrl = "https://koeglfxc96.execute-api.us-east-1.amazonaws.com/dev"
        static let balancesApiUrl = "https://xl77zzdgzi.execute-api.us-east-1.amazonaws.com/dev"
    }
}
