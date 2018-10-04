//
//  VCardEditorViewController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 03/10/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class VCardEditorViewController: NSViewController, AccountAware {
    
    var account: BareJID? {
        didSet {
            guard self.avatarView != nil else {
                return;
            }
            if account == nil {
                self.vcard = nil;
            } else {
                DBVCardStore.instance.vcard(for: account!) { (vcard) in
                    DispatchQueue.main.async {
                        self.vcard = vcard;
                    }
                }
            }
        }
    }
    
    var vcard: VCard! = VCard(vcard4: Element(name: "vcard", xmlns: "urn:ietf:params:xml:ns:vcard-4.0")) {
        didSet {
            if vcard == nil {
                vcard = VCard(vcard4: Element(name: "vcard", xmlns: "urn:ietf:params:xml:ns:vcard-4.0"));
            }
            
            counter = 0;
            
            let uri = vcard.photos.first?.uri;
            avatarView.image = uri == nil ? NSImage(named: NSImage.userName) : NSImage(contentsOf: URL(string: uri!)!);
            givenNameField.stringValue = vcard.givenName ?? "";
            familyNameField.stringValue = vcard.surname ?? "";
            fullNameField.stringValue = vcard.fn ?? "";
            birthdayField.stringValue = vcard.bday ?? "";
            oragnizationField.stringValue = vcard.organizations.first?.name ?? "";
            organiaztionRoleField.stringValue = vcard.role ?? "";
            
            phonesStackView.views.forEach { (v) in
                v.removeFromSuperview();
            }
            vcard.telephones.forEach { p in
                self.addRow(phone: p);
            }
            emailsStackView.views.forEach { (v) in
                v.removeFromSuperview();
            }
            vcard.emails.forEach { (e) in
                self.addRow(email: e);
            }
            addressesStackView.views.forEach { (v) in
                v.removeFromSuperview();
            }
            vcard.addresses.forEach { (a) in
                self.addRow(address: a);
            }
        }
    }
    
    @IBOutlet var avatarView: NSButton!;
    @IBOutlet var givenNameField: NSTextField!;
    @IBOutlet var familyNameField: NSTextField!;
    @IBOutlet var fullNameField: NSTextField!;
    @IBOutlet var birthdayField: NSTextField!;
    @IBOutlet var oragnizationField: NSTextField!;
    @IBOutlet var organiaztionRoleField: NSTextField!;
    
    @IBOutlet var addPhoneButton: NSButton!;
    @IBOutlet var phonesStackView: NSStackView!;
    @IBOutlet var addEmailButton: NSButton!;
    @IBOutlet var emailsStackView: NSStackView!;
    @IBOutlet var addAddressButton: NSButton!;
    @IBOutlet var addressesStackView: NSStackView!;
    
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    @IBOutlet var refreshButton: NSButton!;
    @IBOutlet var refreshButtonWidth: NSLayoutConstraint!;
    @IBOutlet var submitButton: NSButton!;
    
    var counter = 0;
    
    var isEnabled: Bool = false {
        didSet {
            [givenNameField, familyNameField, fullNameField, birthdayField, oragnizationField, organiaztionRoleField].forEach { (field) in
                self.setEnabled(field: field, value: isEnabled);
            }
            addPhoneButton.isHidden = !isEnabled;
            phonesStackView.views.map { (v) -> Row in
                return v as! Row
                }.forEach { (r) in
                    r.isEnabled = isEnabled;
            }
            addEmailButton.isHidden = !isEnabled;
            emailsStackView.views.map { (v) -> Row in
                return v as! Row
                }.forEach { (r) in
                    r.isEnabled = isEnabled;
            }
            addAddressButton.isHidden = !isEnabled;
            addressesStackView.views.map { (v) -> Row in
                return v as! Row
                }.forEach { (r) in
                    r.isEnabled = isEnabled;
            }
            refreshButton.imagePosition = isEnabled ? .noImage : .imageOnly;
            refreshButtonWidth.isActive = !isEnabled;
            submitButton.title = isEnabled ? "Submit" : "Edit";
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        isEnabled = false;
        if account == nil {
            self.vcard = nil;
        } else {
            DBVCardStore.instance.vcard(for: account!) { (vcard) in
                DispatchQueue.main.async {
                    self.vcard = vcard;
                }
            }
        }
    }
    
    func refreshVCard(onSuccess: (()->Void)? = nil, onFailure: ((String)->Void)? = nil) {
        if let account = self.account {
            progressIndicator.startAnimation(self);
            guard let client = XmppService.instance.getClient(for: account), client.state == .connected, let vcard4Module: VCard4Module = client.modulesManager.getModule(VCard4Module.ID) else {
                onFailure?("Account is not connected");
                return;
            }
            vcard4Module.retrieveVCard(onSuccess: { (vcard) in
                DBVCardStore.instance.updateVCard(for: account, on: account, vcard: vcard);
                DispatchQueue.main.async {
                    self.vcard = vcard;
                    self.progressIndicator.stopAnimation(self);
                    onSuccess?();
                }
            }) { (error) in
                print("got error:", error as Any);
                self.progressIndicator.stopAnimation(self);
                onFailure?("Server returned an error: \(error ?? ErrorCondition.remote_server_timeout)");
            }
        }
    }
    
    func nextCounter() -> Int {
        counter = counter + 1;
        return counter;
    }
    
    fileprivate func setEnabled(field: NSTextField, value: Bool) {
        field.isEditable = value;
        field.isBezeled = value;
        field.isBordered = value;
        field.drawsBackground = value;
    }
    
    @IBAction func avatarClicked(_ sender: NSButton) {
        guard isEnabled else {
            return;
        }
        let openFile = NSOpenPanel();
        openFile.worksWhenModal = true;
        openFile.prompt = "Select avatar";
        openFile.canChooseDirectories = false;
        openFile.canChooseFiles = true;
        openFile.canSelectHiddenExtension = true;
        openFile.canCreateDirectories = false;
        openFile.allowsMultipleSelection = false;
        openFile.resolvesAliases = true;
        
        openFile.begin { (response) in
            print("got response", response.rawValue);
            if response == .OK, let url = openFile.url {
                let image = NSImage(contentsOf: url);
                self.avatarView.image = image ?? NSImage(named: NSImage.userName);
                let data = image?.scaledToPng(to: 512);
                self.vcard.photos = data == nil ? [] : [ VCard.Photo(uri: nil, type: "image/png", binval: data!.base64EncodedString(options: []), types: [.home]) ];
            }
        }
    }
    
    @IBAction func addPhone(_ sender: NSButton) {
        let item = VCard.Telephone(uri: nil, kinds: [.cell], types: [.home]);
        vcard.telephones.append(item);
        addRow(phone: item);
    }

    @IBAction func addEmail(_ sender: NSButton) {
        let item = VCard.Email(address: nil, types: [.home]);
        vcard.emails.append(item);
        addRow(email: item);
    }

    @IBAction func addAddress(_ sender: NSButton) {
        let item = VCard.Address(types: [.home]);
        vcard.addresses.append(item);
        addRow(address: item);
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        if isEnabled {
            isEnabled = false;
        }
        refreshVCard(onFailure: { msg in
            DispatchQueue.main.async {
                self.account = self.account;
            }
        });
    }

    @IBAction func submitClicked(_ sender: NSButton) {
        if isEnabled {
            self.view.window?.makeFirstResponder(sender);

            guard let account = self.account, let vcard4Module: VCard4Module = XmppService.instance.getClient(for: account)?.modulesManager.getModule(VCard4Module.ID) else {
                self.handleError(message: "Account is not connected");
                return;
            }
            self.progressIndicator.startAnimation(self);
            vcard4Module.publishVCard(vcard, onSuccess: {
                DBVCardStore.instance.updateVCard(for: account, on: account, vcard: self.vcard);
                DispatchQueue.main.async {
                    self.isEnabled = false;
                    self.progressIndicator.stopAnimation(self);
                }
            }, onError: { error in
                self.progressIndicator.stopAnimation(self);
                self.handleError(message: "Server returned an error: \(error ?? ErrorCondition.remote_server_timeout)");
            });
        } else {
            refreshVCard(onSuccess: {
                DispatchQueue.main.async {
                    self.isEnabled = true;
                }
            }, onFailure: self.handleError)
        }
    }
    
    fileprivate func handleError(message msg: String) {
        DispatchQueue.main.async {
            let alert = NSAlert();
            alert.messageText = "Could not retrive current version from the server.";
            alert.informativeText = msg;
            alert.addButton(withTitle: "OK");
            alert.icon = NSImage(named: NSImage.cautionName);
            alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
        }
    }

    @objc func removePositionClicked(_ sender: NSButton) {
        if let found = phonesStackView.views.firstIndex(where: { (v) -> Bool in
            guard let btn = (v as? NSStackView)?.views.last as? NSButton else {
                return false;
            }
            return btn === sender;
        }) {
            phonesStackView.views[found].removeFromSuperview();
            vcard.telephones.remove(at: found);
        }
        if let found = emailsStackView.views.firstIndex(where: { (v) -> Bool in
            guard let btn = (v as? NSStackView)?.views.last as? NSButton else {
                return false;
            }
            return btn === sender;
        }) {
            emailsStackView.views[found].removeFromSuperview();
            vcard.emails.remove(at: found);
        }
        if let found = addressesStackView.views.firstIndex(where: { (v) -> Bool in
            guard let btn = (v as? NSStackView)?.views.last as? NSButton else {
                return false;
            }
            return btn === sender;
        }) {
            addressesStackView.views[found].removeFromSuperview();
            vcard.addresses.remove(at: found);
        }
    }
    
    fileprivate func addRow(address item: VCard.Address) {
        let tag = nextCounter();
        let streetField = NSTextField(string: item.street ?? "");
        streetField.placeholderString = "Street";
        connect(field: streetField, tag: tag, action: #selector(streetChanged(_:)));
        let zipCodeField = NSTextField(string: item.postalCode ?? "");
        zipCodeField.placeholderString = "Code";
        connect(field: zipCodeField, tag: tag, action: #selector(postalCodeChanged(_:)));
        let cityField = NSTextField(string: item.locality ?? "");
        cityField.placeholderString = "Locality";
        connect(field: cityField, tag: tag, action: #selector(localityChanged(_:)));
        let countryField = NSTextField(string: item.country ?? "");
        countryField.placeholderString = "Country";
        connect(field: countryField, tag: tag, action: #selector(countryChanged(_:)));

        let subdate = NSStackView(views: [zipCodeField, cityField]);
        subdate.orientation = .horizontal;
        zipCodeField.widthAnchor.constraint(equalTo: cityField.widthAnchor, multiplier: 0.4).isActive = true;
        
        let data = NSStackView(views: [streetField, subdate, countryField]);
        data.orientation = .vertical;
        data.spacing = 4;
        
        let stack = Row(views: [createTypeButton(for: item), data, createRemoveButton(for: item)]);
        stack.id = tag;
        stack.orientation = .horizontal;
        stack.alignment = .top;
        stack.spacing = 4;
        addressesStackView.addView(stack, in: .bottom);
        stack.isEnabled = isEnabled;
    }
    
    fileprivate func addRow(email item: VCard.Email) {
        let tag = nextCounter();
        let numberField = NSTextField(string: item.address ?? "");
        numberField.placeholderString = "Enter email address";
        connect(field: numberField, tag: tag, action: #selector(emailChanged(_:)));
        let stack = Row(views: [createTypeButton(for: item), numberField, createRemoveButton(for: item)]);
        stack.id = tag;
        stack.orientation = .horizontal;
        stack.spacing = 4;
        emailsStackView.addView(stack, in: .bottom);
        stack.isEnabled = isEnabled;
    }
    
    fileprivate func addRow(phone item: VCard.Telephone) {
        let tag = nextCounter();
        let numberField = NSTextField(string: item.number ?? "");
        numberField.placeholderString = "Enter phone number";
        connect(field: numberField, tag: tag, action: #selector(phoneNumberChanged(_:)));
        let stack = Row(views: [createTypeButton(for: item), numberField, createRemoveButton(for: item)]);
        stack.id = tag;
        stack.orientation = .horizontal;
        stack.spacing = 4;
        phonesStackView.addView(stack, in: .bottom);
        stack.isEnabled = isEnabled;
    }
    
    fileprivate func connect(field: NSTextField, tag: Int, action: Selector) {
        field.tag = tag;
        field.target = self;
        field.action = action;
        field.sendAction(on: .endGesture)
    }
    
    @IBAction func fieldChanged(_ sender: NSTextField) {
        switch sender {
        case givenNameField:
            vcard.givenName = sender.stringValue.isEmpty ? nil : sender.stringValue;
        case familyNameField:
            vcard.surname = sender.stringValue.isEmpty ? nil : sender.stringValue;
        case fullNameField:
            vcard.fn = sender.stringValue.isEmpty ? nil : sender.stringValue;
        case birthdayField:
            vcard.bday = sender.stringValue.isEmpty ? nil : sender.stringValue;
        case oragnizationField:
            vcard.organizations = sender.stringValue.isEmpty ? [] : [VCard.Organization(name: sender.stringValue)];
        case organiaztionRoleField:
            vcard.role = sender.stringValue.isEmpty ? nil : sender.stringValue;
        default:
            break;
        }
    }
    
    @objc fileprivate func emailChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: emailsStackView, byId: sender.tag) else {
            return;
        }
        vcard.emails[idx].address = value;
    }
    
    @objc fileprivate func phoneNumberChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: phonesStackView, byId: sender.tag) else {
            return;
        }
        vcard.telephones[idx].number = value;
    }
    
    @objc fileprivate func streetChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: addressesStackView, byId: sender.tag) else {
            return;
        }
        vcard.addresses[idx].street = value;
    }

    @objc fileprivate func postalCodeChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: addressesStackView, byId: sender.tag) else {
            return;
        }
        vcard.addresses[idx].postalCode = value;
    }

    @objc fileprivate func localityChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: addressesStackView, byId: sender.tag) else {
            return;
        }
        vcard.addresses[idx].locality = value;
    }

    @objc fileprivate func countryChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: addressesStackView, byId: sender.tag) else {
            return;
        }
        vcard.addresses[idx].country = value;
    }

    fileprivate func findPosition(in stack: NSStackView, byId id: Int) -> Int? {
        return stack.views.firstIndex(where: {(v) -> Bool in
            return ((v as? Row)?.id ?? -1) == id;
        });
    }
    
    fileprivate func createRemoveButton(for item: VCard.VCardEntryItemTypeAware) -> NSButton {
        let removeButton = NSButton(image: NSImage(named: NSImage.removeTemplateName)!, target: self, action: #selector(removePositionClicked));
        removeButton.bezelStyle = .texturedRounded;
        return removeButton;
    }
 
    fileprivate func createTypeButton(for item: VCard.VCardEntryItemTypeAware) -> NSButton {
        let typeButton = NSPopUpButton(frame: .zero, pullsDown: false);
        typeButton.addItem(withTitle: "Home");
        typeButton.addItem(withTitle: "Work");
        typeButton.selectItem(at: item.types.contains(VCard.EntryType.home) ? 0 : 1);
        return typeButton;
    }
    
    class Row: NSStackView {
        
        var id: Int = -1;
        
        var isEnabled: Bool = true {
            didSet {
                if let btn = views.first as? NSButton {
                    btn.isEnabled = isEnabled;
                    btn.isBordered = isEnabled;
                }
                setEnabled(views: self.views, value: isEnabled);
                if let btn = views.last as? NSButton {
                    btn.isHidden = !isEnabled;
                }

            }
        }
        
        fileprivate func setEnabled(views: [NSView], value isEnabled: Bool) {
            views.forEach { (v) in
                if let field = v as? NSTextField {
                    self.setEnabled(field: field, value: isEnabled);
                }
                if let stack = v as? NSStackView {
                    setEnabled(views: stack.views, value: isEnabled);
                }
            }
        }
        
        fileprivate func setEnabled(field: NSTextField, value isEnabled: Bool) {
            field.isEditable = isEnabled;
            field.isBezeled = isEnabled;
            field.isBordered = isEnabled;
            field.drawsBackground = isEnabled;
        }
        
    }
}