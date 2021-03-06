// Copyright © 2018 Conicoin LLC. All rights reserved.
// Created by Artur Guseinov



import Foundation
import RealmSwift
import Alamofire

class SettingsInteractor {
  weak var output: SettingsInteractorOutput!
  
  var keystore: KeystoreServiceProtocol!
  var walletDataStoreService: WalletDataStoreServiceProtocol!
  var pushService: PushServiceProtocol!
  var pushConfigurator: PushConfiguratorProtocol!
  var keychain: Keychain!
  var accountService: AccountServiceProtocol!
  var biometryService: BiometryServiceProtocol!
  var walletRepository: WalletRepository!
}


// MARK: - SettingsInteractorInput

extension SettingsInteractor: SettingsInteractorInput {
  
  var biometry: BiometryType {
    return biometryService.biometry
  }
  
  var passphrase: String {
    guard let oldPin = keychain.passphrase else {
      fatalError("Pin must exist!")
    }
    return oldPin
  }
  
  var accountType: AccountType {
    guard let accountType = accountService.currentAccount?.type else {
      fatalError("Account must exist!")
    }
    return accountType
  }
  
  func getWallet() {
    let wallet = walletRepository.wallet
    output.didReceiveWallet(wallet)
  }
  
  func selectCurrency(_ currency: String) {
    let wallet = walletRepository.wallet
    var updated = wallet
    updated.localCurrency = currency
    output.didReceiveWallet(updated)
    
    DispatchQueue.global().async {
      self.walletDataStoreService.save(updated)
    }
  }
  
  func deleteTempBackup(at url: URL) {
    do {
      try FileManager.default.removeItem(at: url)
    } catch let error {
      output.didFailed(with: error)
    }
  }
  
  func registerForRemoteNotifications() {
    pushService.registerForRemoteNotifications { [unowned self] result in
      switch result {
      case .success:
        print("Registered for remote notifications")
      case .failure(let error):
        print("Failed to register for remote notifications with error: \(error.localizedDescription)")
        self.output.didFailedRegisterForRemoteNotification()
      }
    }
  }
  
  func unregisterFromRemoteNotifications() {
    pushConfigurator.unregister()
    pushService.unregister()
  }
  
  func clearAll(passphrase: String, completion: PinResult?) {
    do {
      // Clear all geth accounts
      try keystore.deleteAllAccounts(passphrase: passphrase)
      
      // Clear keychain
      keychain.deleteAll()
      // Clear defaults
      Defaults.deleteAll()
      // Clear realm
      let realm = try! Realm()
      try! realm.write {
        realm.deleteAll()
      }
      
      // Cancel all requests
      SessionManager.default.session.getAllTasks { tasks in
        tasks.forEach { $0.cancel() }
      }
      
      completion?(.success(true))
    } catch {
      completion?(.failure(error))
    }
  }
    
  func changePin(oldPin: String, newPin: String, completion: PinResult?) {
    do {
      try keystore.changePassphrase(oldPin, new: newPin)
      completion?(.success(true))
    } catch {
      completion?(.failure(error))
    }
  }
  
  func getExportKeyUrl(passcode: String) {
    do {
      guard let keyUrl = try FileManager.default.contentsOfDirectory(atPath: keystore.keystoreUrl).first else {
        throw KeystoreError.noJsonKey
      }
      
      let url = URL(fileURLWithPath: keystore.keystoreUrl + "/" + keyUrl)
      
      let timestamp = Int(Date().timeIntervalSince1970)
      let filename = "conicoin_key_\(timestamp).json"
      let path = NSTemporaryDirectory().appending(filename)
      let tempUrl = URL(fileURLWithPath: path)
      
      let data = try Data(contentsOf: url)
      try data.write(to: tempUrl)
      
      output.didReceiveExportKeyUrl(tempUrl)
    } catch {
      output.didFailed(with: error)
    }
  }
  
}
