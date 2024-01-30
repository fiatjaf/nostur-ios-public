//
//  Event+PrivateNotes.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/03/2023.
//

import Foundation

extension Event {
    var privateNote:CloudPrivateNote? {
        let fr = CloudPrivateNote.fetchRequest()
        fr.predicate = NSPredicate(format: "eventId == %@", self.id)
        fr.fetchLimit = 1
        if Thread.isMainThread {
            return try? DataProvider.shared().viewContext.fetch(fr).first
        }
        else {
            return try? bg().fetch(fr).first
        }
    }
}
