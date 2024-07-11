# 🍎 Apple Pay demo app

## Overview

This project implements various Apple Pay transaction flows on iOS.

It comprises a ticket booking app currently demonstrates how to:
- Use the Apple Pay button
- Display the Apple Pay payment sheet
- Make payment requests (one-off, recurring, funds transfer a.k.a. payout)
- Accept coupon codes
- Filter and validate user input (card network, type, billing/shipping data)
- Handle external API calls ([Checkout.com](https://www.checkout.com/) tokenization, payout eligibility, balance check)

The demo ticket booking app includes flows for buying and selling tickets, and signing up for a subscription service using Apple Pay.

## 🏃 Get started

You will need:
- A Mac
- [Xcode](https://apps.apple.com/us/app/xcode/id497799835?mt=12/)
- Access to an [Apple Developer account](https://developer.apple.com/programs/enroll/)
- **[Optional]** an iPhone or iPad

### Configure the project

1. Sign in [here](https://developer.apple.com/account/resources/identifiers/list/bundleId) and create an App ID. Enable the `Apple Pay Payment Processing` capability and make a note of your `Bundle ID`.

2. Complete steps 1-4 [here](https://www.checkout.com/docs/payments/add-payment-methods/apple-pay#Set_up_Apple_Pay) to create a Merchant ID and register a Payment Processing Certificate with Checkout.com.

3. Open `ApplePayDemo.xcodeproj` in Xcode.

4. Click on the top-level `ApplePayDemo` directory, then under **TARGETS** click on `ApplePayDemo`.

    ![alt text](image-1.png)

5. Under the **General** tab, change the `Bundle Identifier` to your Bundle ID from step 1.

6. Go to the **Build Settings** tab and search for `com.checkout.applepaydemo`; replace any instances with your Bundle ID.

7. Go to the **Signing & Capabilities** tab and add (+) the `Apple Pay` capability. Ensure you have `Automatically manage signing` enabled and your **Team** and **Bundle Identifier** match what's in your developer account. Under **Apple Pay** you should now be able to select your Merchant ID (click refresh if this is not appearing).

### Build and run

In the title bar, you should see the build scheme **iOS App**. Click the option to the right of this which reads **Any iOS Device** in my example below, and a dropdown should appear.

![alt text](image-2.png)

You have 2 options to run the app:

>#### 💻 Simulator
>From the dropdown, select the desired device simulator under **iOS Simulators**.

**OR**

>#### 📱 Device
>1. On your iOS device, open `Settings` > `Privacy & Security` and scroll down to the `Developer Mode` list item. Tap into this and toggle **Developer Mode** on.
>2. In the title bar, you should see the build scheme **iOS App**. Click the option which reads **Any iOS Device** in my example below and dropdown should appear. If your device is connected to the same Wi-Fi network as your Mac, then it should appear automatically to select under **iOS Device**.  Alternatively, you can connect the device to your Mac via USB (make sure your cable can transmit data and isn't charge-only).

&nbsp;

Finally, click the run button (▶️) on the left of the title bar to start the app.


## 📁 Project structure

### **/Shared**

Generic files which can be used across any app.

>#### [`Configuration.swift`](./Shared/Configuration.swift)
>Contains constants for:
>- Apple Merchant ID
>- Checkout.com public API key (for tokenization)
>- API endpoints for backend processing

>#### [`PaymentPaymentHandler.swift`](./Shared/PaymentHandler.swift) [`PayoutPaymentHandler.swift`](./Shared/PayoutHandler.swift) [`RecurringPaymentHandler.swift`](./Shared/RecurringPaymentHandler.swift)
>Classes handling logic for different transaction types within an app.

### **/ApplePayDemo**

Files specific to the demo app.

>#### [`ApplePayDemo.entitlements`](./ApplePayDemo/ApplePayDemo.entitlements)
>A list of merchant IDs used for Apple Pay - replace with your own.

>#### [`AppDelegate.swift`](./ApplePayDemo/AppDelegate.swift) [`SceneDelegate.swift`](./ApplePayDemo/SceneDelegate.swift)
>Boilerplate files for managing app lifecycle.

>#### [`BuyViewController.swift`](./ApplePayDemo/BuyViewController.swift) [`SellViewController.swift`](./ApplePayDemo/SellViewController.swift) [`SubscribeViewController.swift`](./ApplePayDemo/SubscribeViewController.swift)
>Manage UI state for each tab view.

>#### [`Main.storyboard`](./ApplePayDemo/Main.storyboard)
>Design of the app UI, including scenes representing each screen.

>#### [`Assets.xcassets`](./ApplePayDemo/Assets.xcassets/)
>Collection of icons used in the app.

>#### [`LaunchScreen.storyboard`](./ApplePayDemo/Base.lproj/LaunchScreen.storyboard)
>Controls the screen the app launches into.

>#### [`Info.plist`](./ApplePayDemo/Info.plist)
>Configuration details for the app bundle; the file references values from the app's Build Settings.

