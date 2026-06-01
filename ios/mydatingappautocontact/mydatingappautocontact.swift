//
//  mydatingappautocontact.swift
//  mydatingappautocontact
//
//  Created by Eyal Atiya on 01/06/2026.
//

import ExtensionFoundation
import Foundation
import ContactProvider

@main
class mydatingappautocontact: ContactProviderExtension {
    private let rootContainerEnumerator: mydatingappautocontactRootContainerEnumerator

    required init() {
        // Initialize your extension here.
        rootContainerEnumerator = mydatingappautocontactRootContainerEnumerator()
    }

    func configure(for domain: ContactProviderDomain) {
        // Configure your extension here.
        rootContainerEnumerator.configure(for: domain)
    }

    func enumerator(for collection: ContactItem.Identifier) -> ContactItemEnumerator {
        return rootContainerEnumerator
    }

    func invalidate() async throws {
        // TODO: Stop any enumeration and cleanup as the extension will be terminated.
    }
}
