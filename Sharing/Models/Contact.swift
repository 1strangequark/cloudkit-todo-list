//
//  Contact.swift
//  (cloudkit-samples) Sharing
//

import Foundation
import CloudKit

struct Contact: Identifiable {
    let id: String
    let recordID:CKRecord.ID
    let name: String
    let associatedRecord: CKRecord
}

extension Contact {
    /// Initializes a `Contact` object from a CloudKit record.
    /// - Parameter record: CloudKit record to pull values from.
    init?(record: CKRecord) {
        guard let name = record["name"] as? String else {
            return nil
        }

        self.id = record.recordID.recordName
        self.recordID = record.recordID
        self.name = name
        self.associatedRecord = record
    }
}
