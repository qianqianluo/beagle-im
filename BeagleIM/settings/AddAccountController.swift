//
// AddAccountController.swift
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

import AppKit
import TigaseSwift
import Combine

class AddAccountController: NSViewController, NSTextFieldDelegate {
    
    @IBOutlet var logInButton: NSButton!;
    @IBOutlet var stackView: NSStackView!
    @IBOutlet var registerButton: NSButton!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    var usernameField: NSTextField!;
    var passwordField: NSSecureTextField!;
    
    var accountValidatorTask: AccountValidatorTask?;
    
    override func viewWillAppear() {
        super.viewWillAppear();
        usernameField = addRow(label: NSLocalizedString("Username", comment: "account view"), field: NSTextField(string: ""));
        usernameField.placeholderString = "user@domain.com";
        usernameField.delegate = self;
        passwordField = addRow(label: NSLocalizedString("Password", comment: "account view"), field: NSSecureTextField(string: ""));
        passwordField.placeholderString = NSLocalizedString("Required", comment: "account view placeholder");
        passwordField.delegate = self;
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.insertTab(_:)) {
            control.resignFirstResponder();
            
            guard var idx = self.stackView.views.firstIndex(where: { (view) -> Bool in
                view.subviews[1] == control;
            }) else {
                return false;
            }
            
            var responder: NSResponder? = nil;
            repeat {
                idx = idx + 1;
                if idx >= self.stackView.views.count {
                    idx = 0;
                }
                responder = self.stackView.views[idx].subviews[1];
                if !(responder?.acceptsFirstResponder ?? false) {
                    responder = nil;
                }
            } while responder == nil;
            
            self.view.window?.makeFirstResponder(responder);
            
            return true;
        }
        return false;
    }
    
    func controlTextDidChange(_ obj: Notification) {
        logInButton.isEnabled = !(usernameField.stringValue.isEmpty || passwordField.stringValue.isEmpty);
    }
    
    @IBAction func cancelClicked(_ button: NSButton) {
        self.view.window?.sheetParent?.endSheet(self.view.window!)
    }
    
    @IBAction func logInClicked(_ button: NSButton) {
        let jid = BareJID(usernameField.stringValue);
        var account = AccountManager.Account(name: jid);
        account.password = passwordField.stringValue;
        self.showProgressIndicator();
        self.accountValidatorTask = AccountValidatorTask(controller: self);
        self.accountValidatorTask?.check(account: account.name, password: account.password!, callback: { result in
            let certificateInfo = self.accountValidatorTask?.acceptedCertificate;
            DispatchQueue.main.async {
                self.accountValidatorTask?.finish();
                self.accountValidatorTask = nil;
                self.hideProgressIndicator();
                switch result {
                case .success(_):
                    if let certInfo = certificateInfo {
                        account.serverCertificate = ServerCertificateInfo(sslCertificateInfo: certInfo, accepted: true);
                    }
                    
                    do {
                        try AccountManager.save(account: account);
                        self.view.window?.sheetParent?.endSheet(self.view.window!);
                    } catch {
                        let alert = NSAlert(error: error);
                        alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
                    }
                case .failure(let error):
                    let alert = NSAlert();
                    alert.alertStyle = .critical;
                    alert.messageText = NSLocalizedString("Authentication failed", comment: "alert window title");
                    switch error {
                    case .not_authorized:
                        alert.informativeText = NSLocalizedString("Login and password do not match.", comment: "alert window message");
                    default:
                        alert.informativeText = NSLocalizedString("It was not possible to contact XMPP server and sign in.", comment: "alert window message");
                    }
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { _ in
                        // nothing to do.. just wait for user interaction
                    })
                    break;
                }
            }
        })
    }
    
    private func showProgressIndicator() {
        self.registerButton.isEnabled = false;
        self.logInButton.isEnabled = false;
        progressIndicator.startAnimation(self);
    }
    
    private func hideProgressIndicator() {
        self.logInButton.isEnabled = true;
        self.registerButton.isEnabled = true;
        progressIndicator.stopAnimation(self);
    }
    
    @IBAction func registerClicked(_ button: NSButton) {
        guard let registerAccountController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("RegisterAccountController")) as? RegisterAccountController else {
            self.view.window?.sheetParent?.endSheet(self.view.window!);
            return;
        }
        
        let window = NSWindow(contentViewController: registerAccountController);
        self.view.window?.beginSheet(window, completionHandler: { (reponse) in
            self.view.window?.sheetParent?.endSheet(self.view.window!);
        })
    }
    
    func addRow<T: NSView>(label text: String, field: T) -> T {
        let label = createLabel(text: text);
        let row = RowView(views: [label, field]);
        self.stackView.addView(row, in: .bottom);
        return field;
    }
    
    func createLabel(text: String) -> NSTextField {
        let label = NSTextField(string: text);
        label.isEditable = false;
        label.isBordered = false;
        label.drawsBackground = false;
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true;
        label.alignment = .right;
        return label;
    }
    
    class RowView: NSStackView {
    }

    class AccountValidatorTask: EventHandler {
        
        private var cancellable: AnyCancellable?;
        var client: XMPPClient? {
            willSet {
                if newValue != nil {
                    newValue?.eventBus.register(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE);
                }
            }
            didSet {
                if oldValue != nil {
                    _ = oldValue?.disconnect(true);
                    oldValue?.eventBus.unregister(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE);
                }
                cancellable = client?.$state.sink(receiveValue: { [weak self] state in self?.changedState(state) });
            }
        }
        
        var callback: ((Result<Void,ErrorCondition>)->Void)? = nil;
        weak var controller: AddAccountController?;
        var dispatchQueue = DispatchQueue(label: "accountValidatorSync");
        
        var acceptedCertificate: SslCertificateInfo? = nil;
        
        init(controller: AddAccountController) {
            self.controller = controller;
            initClient();
        }
        
        fileprivate func initClient() {
            self.client = XMPPClient();
            _ = client?.modulesManager.register(StreamFeaturesModule());
            _ = client?.modulesManager.register(SaslModule());
            _ = client?.modulesManager.register(AuthModule());
        }
        
        public func check(account: BareJID, password: String, callback: @escaping (Result<Void,ErrorCondition>)->Void) {
            self.callback = callback;
            client?.connectionConfiguration.useSeeOtherHost = false;
            client?.connectionConfiguration.userJid = account;
            client?.connectionConfiguration.credentials = .password(password: password, authenticationName: nil, cache: nil);
            client?.login();
        }
        
        public func handle(event: Event) {
            dispatchQueue.sync {
                guard let callback = self.callback else {
                    return;
                }
                var param: ErrorCondition? = nil;
                switch event {
                case is SaslModule.SaslAuthSuccessEvent:
                    param = nil;
                case is SaslModule.SaslAuthFailedEvent:
                    param = ErrorCondition.not_authorized;
                default:
                    param = ErrorCondition.service_unavailable;
                }
                
                DispatchQueue.main.async {
                    if let error = param {
                        callback(.failure(error));
                    } else {
                        callback(.success(Void()));
                    }
                }
                self.finish();
            }
        }
        
        func changedState(_ state: XMPPClient.State) {
            dispatchQueue.sync {
                guard let callback = self.callback else {
                    return;
                }

                switch state {
                case .disconnected(let reason):
                    switch reason {
                    case .sslCertError(let trust):
                        self.callback = nil;
                        let certData = SslCertificateInfo(trust: trust);
                        DispatchQueue.main.async {
                            let alert = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "ServerCertificateErrorController") as! ServerCertificateErrorController;
                            _ = alert.view;
                            alert.account = self.client?.sessionObject.userBareJid;
                            alert.certficateInfo = certData;
                            alert.completionHandler = { accepted in
                                self.acceptedCertificate = certData;
                                if (accepted) {
                                    self.client?.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
                                        options.networkProcessorProviders.append(SSLProcessorProvider());
                                        options.sslCertificateValidation = .fingerprint(certData.details.fingerprintSha1);
                                    });
                                    self.callback = callback;
                                    self.client?.login();
                                } else {
                                    self.finish();
                                    DispatchQueue.main.async {
                                        callback(.failure(.service_unavailable));
                                    }
                                }
                            };
                            self.controller?.presentAsSheet(alert);
                        }
                        return;
                    default:
                        break;
                    }
                    DispatchQueue.main.async {
                        callback(.failure(.service_unavailable));
                    }
                    self.finish();
                default:
                    break;
                }
            }
        }
        
        public func finish() {
            self.callback = nil;
            self.client = nil;
            self.controller = nil;
        }
    }
}
