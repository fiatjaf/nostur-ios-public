//
//  NRState.swift
//  Nostur
//
//  Created by Fabian Lachman on 19/09/2023.
//

import SwiftUI

class NRState: ObservableObject {
    
    @AppStorage("main_wot_account_pubkey") private var mainAccountWoTpubkey = ""
    @MainActor public static let shared = NRState()
    
    // view context
    @Published public var accounts:[Account] = [] {
        didSet {
            let accountPubkeys = Set(accounts.map { $0.publicKey })
            let fullAccountPubkeys = Set(accounts.filter { $0.privateKey != nil }.map { $0.publicKey })
            bg().perform {
                self.accountPubkeys = accountPubkeys
                self.fullAccountPubkeys = fullAccountPubkeys
            }
        }
    }

    @Published public var loggedInAccount:LoggedInAccount? = nil
    public var wot:WebOfTrust
    public var nsecBunker:NSecBunkerManager
    
    @Published var onBoardingIsShown = false {
        didSet {
            sendNotification(.onBoardingIsShownChanged, onBoardingIsShown)
        }
    }
    @Published var readOnlyAccountSheetShown:Bool = false
    var rawExplorePubkeys:Set<String> = []
    
    @MainActor public func logout(_ account:Account) {
        if (account.privateKey != nil) {
            if account.isNC {
                NIP46SecretManager.shared.deleteSecret(account: account)
            }
            else {
                AccountManager.shared.deletePrivateKey(forPublicKeyHex: account.publicKey)
            }
        }
        DataProvider.shared().viewContext.delete(account)
        DataProvider.shared().save()
        self.loadAccounts() { accounts in
            guard let nextAccount = accounts.last else {
                sendNotification(.clearNavigation)
                self.activeAccountPublicKey = ""
                self.onBoardingIsShown = true
                self.loggedInAccount = nil
                return
            }
            
            self.loadAccount(nextAccount)
        }
    }
    
    @MainActor public func changeAccount(_ account:Account? = nil) {
        guard let account = account else {
            self.loggedInAccount = nil
            self.activeAccountPublicKey = ""
            return
        }
        
        self.nsecBunker.setAccount(account)
        let pubkey = account.publicKey
        self.loggedInAccount = LoggedInAccount(account)
        
        guard pubkey != self.activeAccountPublicKey else { return }
        self.activeAccountPublicKey = pubkey
        if mainAccountWoTpubkey == "" {
            wot.guessMainAccount()
        }
    }
    
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    
    // BG high speed vars
    public var accountPubkeys:Set<String> = []
    public var fullAccountPubkeys:Set<String> = []
    public var mutedWords:[String] = [] {
        didSet {
//            sendNotification(.mutedWordsChanged, mutedWords) // TODO update listeners
        }
    }
    
    @MainActor private init() {
        self.wot = WebOfTrust.shared
        self.nsecBunker = NSecBunkerManager.shared
        signpost(self, "LAUNCH", .begin, "Initializing Nostur App State")
        let activeAccountPublicKey = activeAccountPublicKey
        loadAccounts() { accounts in
            guard !activeAccountPublicKey.isEmpty,
                    let account = try? Account.fetchAccount(publicKey: activeAccountPublicKey, context: DataProvider.shared().viewContext)
            else { return }
            self.loadAccount(account)
        }
        managePowerUsage()
        loadMutedWords()
    }
    
    @MainActor public func loadAccounts(onComplete: (([Account]) -> Void)? = nil) { // main context
        let r = Account.fetchRequest()
        guard let accounts = try? DataProvider.shared().viewContext.fetch(r) else { return }
        self.accounts = accounts
        onComplete?(accounts)
    }
    
    @MainActor public func loadAccount(_ account:Account) { // main context
        guard loggedInAccount == nil || account.publicKey != self.activeAccountPublicKey else {
            L.og.notice("🔴🔴 This account is already loaded")
            return
        }
        self.activeAccountPublicKey = account.publicKey
        self.nsecBunker.setAccount(account)
        self.loggedInAccount = LoggedInAccount(account)
    }
    
    private func managePowerUsage() {
        NotificationCenter.default.addObserver(self, selector: #selector(powerStateChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
    }
    
    public func loadMutedWords() {
        bg().perform {
            let fr = MutedWords.fetchRequest()
            fr.predicate = NSPredicate(format: "enabled == true")
            guard let mutedWords = try? bg().fetch(fr) else { return }
            self.mutedWords = mutedWords.map { $0.words }.compactMap { $0 }.filter { $0 != "" }
        }
    }
    
    @objc func powerStateChanged(_ notification: Notification) {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            if SettingsStore.shared.animatedPFPenabled {
                SettingsStore.shared.objectWillChange.send() // This will reload views to stop playing animated PFP GIFs
            }
        }
    }
    
    // Other
    public var nrPostQueue = DispatchQueue(label: "com.nostur.nrPostQueue", attributes: .concurrent)
    
    let agoTimer = Timer.publish(every: 60, tolerance: 15.0, on: .main, in: .default).autoconnect()
}

func notMain() {
    #if DEBUG
        if Thread.isMainThread && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            fatalError("Should only be called from bg()")
        }
    #endif
}

func isFollowing(_ pubkey:String) -> Bool {
    if Thread.isMainThread {
        return NRState.shared.loggedInAccount?.viewFollowingPublicKeys.contains(pubkey) ?? false
    }
    else {
        return NRState.shared.loggedInAccount?.followingPublicKeys.contains(pubkey) ?? false
    }
}

func followingPFP(_ pubkey: String) -> URL? {
    NRState.shared.loggedInAccount?.followingPFPs[pubkey]
}

func account() -> Account? {
    if Thread.isMainThread {
        NRState.shared.loggedInAccount?.account
    }
    else {
        NRState.shared.loggedInAccount?.bgAccount
    }
}

func follows() -> Set<String> {
    if Thread.isMainThread {
        NRState.shared.loggedInAccount?.viewFollowingPublicKeys ?? []
    }
    else {
        NRState.shared.loggedInAccount?.followingPublicKeys ?? []
    }
}

func blocks() -> Set<String> {
    if Thread.isMainThread {
        NRState.shared.loggedInAccount?.account.blockedPubkeys_ ?? []
    }
    else {
        NRState.shared.loggedInAccount?.bgAccount?.blockedPubkeys_ ?? []
    }
}


func isFullAccount(_ account:Account? = nil ) ->Bool {
    if Thread.isMainThread {
        return (account ?? NRState.shared.loggedInAccount?.account)?.privateKey != nil
    }
    else {
        return (account ?? NRState.shared.loggedInAccount?.bgAccount)?.privateKey != nil
    }
}

func showReadOnlyMessage() {
    NRState.shared.readOnlyAccountSheetShown = true;
}

final class ExchangeRateModel: ObservableObject {
    static public var shared = ExchangeRateModel()
    @Published var bitcoinPrice:Double = 0.0
}


let IS_IPAD = UIDevice.current.userInterfaceIdiom == .pad
let IS_CATALYST = ProcessInfo.processInfo.isMacCatalystApp
let IS_APPLE_TYRANNY = ((Bundle.main.infoDictionary?["NOSTUR_IS_DESKTOP"] as? String) ?? "NO") == "NO"
//let IS_MAC = ProcessInfo.processInfo.isiOSAppOnMac


let GUEST_ACCOUNT_PUBKEY = "c118d1b814a64266730e75f6c11c5ffa96d0681bfea594d564b43f3097813844"
let EXPLORER_PUBKEY = "afba415fa31944f579eaf8d291a1d76bc237a527a878e92d7e3b9fc669b14320"


var timeTrackers: [String: CFAbsoluteTime] = [:]
