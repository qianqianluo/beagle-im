//
// AccountManager.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//

import Foundation
import Security
import TigaseSwift
import Combine

open class AccountManager {

    private static let dispatcher = QueueDispatcher(label: "AccountManager");
    private static var accounts: [BareJID: Account] = [:];
    
    static let accountEventsPublisher = PassthroughSubject<Event,Never>();
    
    static var defaultAccount: BareJID? {
        get {
            return BareJID(Settings.defaultAccount);
        }
        set {
            Settings.defaultAccount = newValue?.stringValue;
        }
    }
    
    static func getAccounts() -> [BareJID] {
        return self.dispatcher.sync {
            guard accounts.isEmpty else {
                return Array(accounts.keys).sorted(by: { (j1, j2) -> Bool in
                    j1.stringValue.compare(j2.stringValue) == .orderedAscending
                });
            }
            
            let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: kCFBooleanTrue as Any, kSecAttrService as String: "xmpp"];
            var result: CFTypeRef?;
            
            guard SecItemCopyMatching(query as CFDictionary, &result) == noErr else {
                return [];
            }
            
            guard let results = result as? [[String: NSObject]] else {
                return [];
            }
            
            let accounts = results.filter({ $0[kSecAttrAccount as String] != nil}).map { item -> BareJID in
                return BareJID(item[kSecAttrAccount as String] as! String);
                }.sorted(by: { (j1, j2) -> Bool in
                    j1.stringValue.compare(j2.stringValue) == .orderedAscending
                });
            
            for account in accounts {
                if let item = getAccountInt(for: account) {
                    self.accounts[account] = item;
                }
            }
            return accounts;
        }
    }
    
    static func getActiveAccounts() -> [Account] {
        return getAccounts().compactMap({ jid -> Account? in
            guard let account = getAccount(for: jid), account.active else {
                return nil;
            }
            return account;
        });
    }
    
    static func getAccount(for jid: BareJID) -> Account? {
        return self.dispatcher.sync {
            return self.accounts[jid];
        }
    }
    
    private static func getAccountInt(for jid: BareJID) -> Account? {
        let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecMatchLimit as String: kSecMatchLimitOne, kSecReturnAttributes as String: kCFBooleanTrue as Any, kSecAttrService as String: "xmpp" as NSObject, kSecAttrAccount as String : jid.stringValue as NSObject ];
        
        var result: CFTypeRef?;
        
        guard SecItemCopyMatching(query as CFDictionary, &result) == noErr else {
            return nil;
        }
        
        guard let r = result as? [String: NSObject] else {
            return nil;
        }
        
        let dict = AccountManager.parseDict(from: r[kSecAttrGeneric as String] as? Data);
        
        return Account(name: jid, data: dict);
    }
    
    static func save(account toSave: Account) throws {
        try self.dispatcher.sync {
            var account = toSave;
            var query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "xmpp" as NSObject, kSecAttrAccount as String : account.name.stringValue as NSObject ];
            var update: [String: Any] = [ kSecAttrGeneric as String: try! NSKeyedArchiver.archivedData(withRootObject: account.data, requiringSecureCoding: false), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock];
            if let newPassword = account.newPassword {
                update[kSecValueData as String] = newPassword.data(using: .utf8)!;
            }

            if getAccount(for: account.name) == nil {
                query.merge(update) { (v1, v2) -> Any in
                    return v1;
                }
                if let error = AccountManagerError(status: SecItemAdd(query as CFDictionary, nil)) {
                    throw error;
                }
            } else {
                if let error = AccountManagerError(status: SecItemUpdate(query as CFDictionary, update as CFDictionary)) {
                    throw error;
                }
            }
            
                account.newPassword = nil;
            
            if defaultAccount == nil {
                defaultAccount = account.name;
            }
             
            self.accounts[account.name] = account;
            
            DispatchQueue.main.async {
                self.accountEventsPublisher.send(account.active ? .enabled(account) : .disabled(account));
            }
        }
    }
    
    static func delete(account: Account) throws {
        try dispatcher.sync {
            let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "xmpp" as NSObject, kSecAttrAccount as String : account.name.stringValue as NSObject ];
            
            if let error = AccountManagerError(status: SecItemDelete(query as CFDictionary)) {
                throw error;
            }
            
            if let defAccount = defaultAccount, defAccount == account.name {
                defaultAccount = getAccounts().first;
            }

            self.accounts.removeValue(forKey: account.name);

            DispatchQueue.main.async {
                self.accountEventsPublisher.send(.removed(account));
            }
        }
    }
    
    static fileprivate func parseDict(from data: Data?) -> [String: Any]? {
        guard data != nil else {
            return nil;
        }
        
        return try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data!) as? [String: Any];
    }
        
    enum Event {
        case enabled(Account)
        case disabled(Account)
        case removed(Account)
    }
    
    struct AccountManagerError: LocalizedError, CustomDebugStringConvertible {
        let status: OSStatus;
        let message: String?;
        
        var errorDescription: String? {
            return NSLocalizedString("It was not possible to modify account.", comment: "account manager error") + "\n" + (message ?? (NSLocalizedString("Error code", comment: "account manager error") + ": \(status)"));
        }
        
        var failureReason: String? {
            return message;
        }
        
        var recoverySuggestion: String? {
            return NSLocalizedString("Try again. If removal failed, try accessing Keychain to update account credentials manually.", comment: "account manager error");
        }
        
        var debugDescription: String {
            return "AccountManagerError(status: \(status), message: \(message ?? "nil"))";
        }
        
        init?(status: OSStatus) {
            guard status != noErr else {
                return nil;
            }
            self.status = status;
            message = SecCopyErrorMessageString(status, nil) as String?;
        }
    }
    
    struct Account {
        
        public var state = CurrentValueSubject<XMPPClient.State,Never>(.disconnected());
        
        fileprivate var data: [String: Any];
        fileprivate var newPassword: String?;
        
        public let name: BareJID;
        
        public var password: String? {
            get {
                guard newPassword == nil else {
                    return newPassword;
                }
                return getPassword();
            }
            set {
                self.newPassword = newValue;
            }
        }
        
        public var active: Bool {
            get {
                return data["active"] as? Bool ?? false;
            }
            set {
                data["active"] = newValue;
            }
        }
        
        public var nickname: String? {
            get {
                guard let nick = data["nickname"] as? String, !nick.isEmpty else {
                    return name.localPart;
                }
                return nick;
            }
            set {
                if newValue == nil {
                    data.removeValue(forKey: "nickname");
                } else {
                    data["nickname"] = newValue;
                }
            }
        }
        
        public var resourceType: ResourceType {
            get {
                guard let val = data["resourceType"] as? String, let r = ResourceType(rawValue: val) else {
                    return .automatic;
                }
                return r;
            }
            set {
                data["resourceType"] = newValue.rawValue;
            }
        }
        
        public var resourceName: String? {
            get {
                return data["resourceName"] as? String;
            }
            set {
                if newValue == nil {
                    data.removeValue(forKey: "resourceName")
                } else {
                    data["resourceName"] = newValue;
                }
            }
        }
        
        public var serverCertificate: ServerCertificateInfo? {
            get {
                return data["serverCertificateInfo"] as? ServerCertificateInfo;
            }
            set {
                if newValue == nil {
                    data.removeValue(forKey: "serverCertificateInfo");
                } else {
                    data["serverCertificateInfo"] = newValue;
                }
            }
        }
        
        public init(name: BareJID) {
            self.name = name;
            self.data = ["active": true];
        }
        
        fileprivate init(name: BareJID, data: [String: Any]?) {
            self.name = name;
            self.data = data ?? [:];
        }
        
        fileprivate func getPassword() -> String? {
            let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecMatchLimit as String: kSecMatchLimitOne, kSecReturnData as String: kCFBooleanTrue as Any, kSecAttrService as String: "xmpp" as NSObject, kSecAttrAccount as String : name.stringValue as NSObject ];
            var result: CFTypeRef?;
                
            let r = SecItemCopyMatching(query as CFDictionary, &result);
            guard r == noErr else {
                return nil;
            }
                
            guard let data = result as? Data else {
                return nil;
            }
                
            return String(data: data, encoding: .utf8);
        }
     
        enum ResourceType: String {
            case automatic
            case hostname
            case custom
        }
    }
}
