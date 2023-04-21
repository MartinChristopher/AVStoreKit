//
//  AVStoreKit.swift
//  BangLive
//
//  Created by Apple on 2023/4/20.
//

import UIKit
import StoreKit

#if DEBUG
let checkURL = "https://sandbox.itunes.apple.com/verifyReceipt"
#else
let checkURL = "https://buy.itunes.apple.com/verifyReceipt"
#endif

@objc public protocol AVStoreKitDelegate: NSObjectProtocol {
    // 购买成功
    @objc func successWith(_ productId: String, info: [String: Any])
    // 取消购买
    @objc func cancelWith(_ productId: String)
    // 验证购买
    @objc func checkingWith(_ productId: String)
    // 验证失败
    @objc func checkFailedWith(_ productId: String)
    // 恢复已购买商品
    @objc func restoredWith(_ productId: String)
    // 系统错误
    @objc func systemWrong()
    
}

public class AVStoreKit: NSObject, SKPaymentTransactionObserver, SKProductsRequestDelegate {
    
    public static let shared = AVStoreKit()
    
    public weak var delegate: AVStoreKitDelegate?
    
    public var checkAfterPay: Bool = true
    
    private var currentId: String!
    
    public override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    public func requestProductWith(_ productId: String) {
        print("📢 请求商品")
        currentId = productId
        let request = SKProductsRequest(productIdentifiers: [productId])
        request.delegate = self
        request.start()
    }
    
    public func restoreProduct() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            if SKPaymentTransactionState.purchased == transaction.transactionState {
                print("📢 购买完成")
                if checkAfterPay {
                    delegate?.checkingWith(transaction.payment.productIdentifier)
                    verifyProductWith(transaction.payment.productIdentifier)
                }
                else {
                    guard let receiptURL = Bundle.main.appStoreReceiptURL,
                          let receiptData = try? Data(contentsOf: receiptURL) else { return }
                    let receiptStr = receiptData.base64EncodedString(options: .endLineWithLineFeed)
                    delegate?.successWith(transaction.payment.productIdentifier, info: ["receipt": receiptStr])
                }
                SKPaymentQueue.default().finishTransaction(transaction)
            }
            else if SKPaymentTransactionState.restored == transaction.transactionState {
                print("📢 恢复成功")
                delegate?.restoredWith(transaction.payment.productIdentifier)
                SKPaymentQueue.default().finishTransaction(transaction)
            }
            else if SKPaymentTransactionState.failed == transaction.transactionState {
                SKPaymentQueue.default().finishTransaction(transaction)
                delegate?.cancelWith(transaction.payment.productIdentifier)
            }
            else if SKPaymentTransactionState.purchasing == transaction.transactionState {
                print("📢 正在购买")
            }
            else {
                print("📢 已经购买")
                SKPaymentQueue.default().finishTransaction(transaction)
            }
        }
    }
    
    private func verifyProductWith(_ productId: String) {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let receiptData = try? Data(contentsOf: receiptURL) else { return }
        let receiptStr = receiptData.base64EncodedString(options: .endLineWithLineFeed)
        let payload = String(format: "{\"receipt-data\" : \"%@\"}", receiptStr)
        let payloadData = payload.data(using: .utf8)
        var request = URLRequest(url: URL(string: checkURL)!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = payloadData
        URLSession.shared.dataTask(with: request) { [weak self] (data, response, error) in
            if error != nil {
                print("📢 验证失败")
                self?.delegate?.checkFailedWith(productId)
            }
            else {
                if let data = data,
                   let dic = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String : Any] {
                    self?.delegate?.successWith(productId, info: dic)
                }
                else {
                    print("📢 验证失败")
                    self?.delegate?.checkFailedWith(productId)
                }
            }
        }.resume()
    }
    
    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        if response.products.isEmpty {
            print("📢 商品错误")
            delegate?.systemWrong()
            return
        }
        var product: SKProduct?
        for item in response.products {
            if item.productIdentifier == currentId {
                product = item
                break
            }
        }
        if product != nil {
            print("📢 销售商品", product as Any)
            let payment = SKPayment(product: product!)
            SKPaymentQueue.default().add(payment)
        }
    }
    
}
