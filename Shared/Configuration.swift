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
        static let identifier = "merchant.checkout.applepaydemo"
    }
    
    struct CheckoutDotCom {
        static let publicKey = "pk_sbox_svm7ctgfxkhbfthi4blfb765nyq"
    }
    
    struct Server {
        static let metadataApiUrl = "https://koeglfxc96.execute-api.us-east-1.amazonaws.com/dev"
    }
}
