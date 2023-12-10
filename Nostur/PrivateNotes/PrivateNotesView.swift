//
//  PrivateNotesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/11/2023.
//

import SwiftUI
import Combine
import CoreData

struct PrivateNotesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themes:Themes
    @EnvironmentObject private var ns:NRState
    
    private var selectedSubTab: String {
        get { UserDefaults.standard.string(forKey: "selected_bookmarkssubtab") ?? "Private Notes" }
        set { UserDefaults.standard.setValue(newValue, forKey: "selected_bookmarkssubtab") }
    }
    
    @Binding var navPath:NavigationPath
    @ObservedObject private var settings:SettingsStore = .shared
    @Namespace private var top
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt, order: .reverse)])
    private var privateNotes: FetchedResults<CloudPrivateNote>
    
    @State private var events:[Event] = [] // bg
    @State private var contacts:[Contact] = [] // main
    @State private var privateNotesSnapshot: Int = 0
    @State private var noEvents = false
    @State private var noContacts = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 1).id(top)
                if !privateNotes.isEmpty && (!events.isEmpty || noEvents) && (!contacts.isEmpty || noContacts) {
                    LazyVStack(spacing: 10) {
                        ForEach(privateNotes) { pn in
                            LazyPrivateNote(pn: pn, events: events, contacts: contacts)
                                .onDelete {
                                    viewContext.delete(pn)
                                    viewContext.transactionAuthor = "removeCloudPrivateNote"
                                    DataProvider.shared().save()
                                    viewContext.transactionAuthor = nil
                                }
                        }
                        Spacer()
                    }
                    .background(themes.theme.listBackground)
                    .preference(key: PrivateNotesCountPreferenceKey.self, value: privateNotes.count.description)
                }
                else {
                    Text("When you bookmark a post it will show up here.")
                        .hCentered()
                        .padding(.top, 40)
                }
            }
            .onReceive(receiveNotification(.didTapTab)) { notification in
                guard selectedSubTab == "Bookmarks" else { return }
                guard let tabName = notification.object as? String, tabName == "Bookmarks" else { return }
                if navPath.count == 0 {
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
            }
        }
        .navigationTitle(String(localized:"Bookmarks", comment:"Navigation title for Bookmarks screen"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .onReceive(privateNotes.publisher.collect()) { bookmarks in
            let currentSnapshot = privateNotes.compactMap { (($0.type ?? "") + $0.content_ + (($0.eventId ?? $0.pubkey) ?? "")) }.hashValue
            if currentSnapshot != privateNotesSnapshot {
                // Update the snapshot to the current state.
                privateNotesSnapshot = currentSnapshot
                if privateNotes.count != (events.count + contacts.count) {
                    load()
                }
            }
        }
        .simultaneousGesture(
            DragGesture().onChanged({
                if 0 < $0.translation.height {
                    sendNotification(.scrollingUp)
                }
                else if 0 > $0.translation.height {
                    sendNotification(.scrollingDown)
                }
            }))
    }
    
    private func load() {
        L.cloud.debug("Loading")
        var uniqueEventIds = Set<String>()
        var uniqueContactPubkeys = Set<String>()
        let sortedPrivateNotes = privateNotes.sorted {
            ($0.createdAt as Date?) ?? Date.distantPast > ($1.createdAt as Date?) ?? Date.distantPast
        }
        
        let duplicates = sortedPrivateNotes
            .filter { pn in
                if let eventId = pn.eventId {
                    return !uniqueEventIds.insert(eventId).inserted
                }
                else if let pubkey = pn.pubkey {
                    return !uniqueContactPubkeys.insert(pubkey).inserted
                }
                return false
            }
        
        L.cloud.debug("Deleting: \(duplicates.count) duplicate private notes")
        duplicates.forEach {
            DataProvider.shared().viewContext.delete($0)
        }
        if !duplicates.isEmpty {
            DataProvider.shared().save()
        }
        
        let pnEventIds = privateNotes.compactMap { $0.eventId }
        let pnContactPubkeys = privateNotes.compactMap { $0.pubkey }
        
        let fr3 = Contact.fetchRequest()
        fr3.predicate = NSPredicate(format: "pubkey IN %@", pnContactPubkeys )
        fr3.returnsObjectsAsFaults = false
        contacts = (try? viewContext.fetch(fr3)) ?? []
        if contacts.count == 0 {
            noContacts = true
        }
        
        bg().perform {
            let fr2 = Event.fetchRequest()
            fr2.predicate = NSPredicate(format: "id IN %@", pnEventIds )
            events = (try? bg().fetch(fr2)) ?? []
            if events.count == 0 {
                noEvents = true
            }
        }
    }
}

#Preview("Private Notes") {
    PreviewContainer({ pe in
        pe.loadPosts()
        pe.loadPrivateNotes()
    }) {
        VStack {
            BookmarksView(navPath: .constant(NavigationPath()))
        }
    }
}

struct LazyPrivateNote: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themes:Themes
    @ObservedObject private var settings:SettingsStore = .shared
    
    @ObservedObject public var pn:CloudPrivateNote
    public var events:[Event] // bg
    public var contacts:[Contact] // main
    
    @State private var viewState:ViewState = .loading
    @State private var nrPost:NRPost? // main
//    @State private var contact:Contact? // main
    @State private var backlog:Backlog?
    
    enum ViewState {
        case loading
        case readyPost(NRPost)
        case readyContact(ContactInfo)
        case error(String)
    }
    
    // Workaround, if we just use Contact, Contact just disappears after viewContext.save()
    // Seems using @State var contact:Contact? or @State var viewState = .readyContact(contact)
    // is not enough to keep the Contact in memory for view, can't figure out why.
    // So we just keep the contact info here in a seperate struct
    struct ContactInfo {
        let pubkey:String
        var pictureUrl:URL?
        let anyName:String
        var about:String?
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        Box(nrPost: nrPost) {
            VStack(spacing: 0) {
                
                HStack(alignment:.top) {
                    Text(pn.content_ == "" ? "(Empty note)" : pn.content_)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            sendNotification(.editingPrivateNote, pn)
                        }
                    Spacer()
                    Ago(pn.createdAt_)
                        .equatable()
                        .frame(alignment: .trailing)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 5)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
                
                switch viewState {
                case .loading:
                    ProgressView()
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .task {
                            guard let type = pn.type else { return }
                            if type == CloudPrivateNote.PrivateNoteType.post.rawValue {
                                loadPost()
                            }
                            else if type == CloudPrivateNote.PrivateNoteType.contact.rawValue {
                                loadContact()
                            }
                        }
                case .readyPost(let nrPost):
                    HStack {
                        PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 25)
                            .onTapGesture {
                                if let nrContact = nrPost.contact {
                                    navigateTo(nrContact)
                                }
                                else {
                                    navigateTo(ContactPath(key: nrPost.pubkey))
                                }
                            }
                        
                        MinimalNoteTextRenderView(nrPost: nrPost, lineLimit: 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { navigateTo(nrPost) }
                    }
                    
                case .readyContact(let contactInfo):
                    HStack {
                        InnerPFP(pubkey: contactInfo.pubkey, pictureUrl: contactInfo.pictureUrl, size: 25)
                        Text(contactInfo.anyName) // Name
                            .foregroundColor(.secondary)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .layoutPriority(2)
                       
                        Text(contactInfo.about ?? "").lineLimit(1)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        navigateTo(ContactPath(key: contactInfo.pubkey))
                    }
                case .error(let message):
                    HStack {
                        Text(message)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }
    
    private func loadPost() {
        guard let eventId = pn.eventId else { viewState = .error("Cannot find post"); return }
        let json = pn.json
        bg().perform {
            if let event = events.first(where: { $0.id == eventId }) {
                let nrPost = NRPost(event: event)
                DispatchQueue.main.async {
                    self.nrPost = nrPost
                    self.viewState = .readyPost(nrPost)
                }
            }
            else {
                let decoder = JSONDecoder()
                if let json = json, let jsonData = json.data(using: .utf8, allowLossyConversion: false) {
                    if let nEvent = try? decoder.decode(NEvent.self, from: jsonData) {
                        let savedEvent = Event.saveEvent(event: nEvent, relays: "iCloud")
                        let nrPost = NRPost(event: savedEvent)
                        L.cloud.debug("Decoded and saved from iCloud: \(nEvent.id) ")
                        DispatchQueue.main.async {
                            self.nrPost = nrPost
                            self.viewState = .readyPost(nrPost)
                        }
                    }
                }
            }
        }
    }
    
    private func loadContact() {
        guard let pubkey = pn.pubkey else { viewState = .error("Cannot find pubkey"); return }
        let json = pn.json
        if let contact = contacts.first(where: { $0.pubkey == pubkey }) {
            self.viewState = .readyContact(ContactInfo(pubkey: contact.pubkey, pictureUrl: contact.pictureUrl, anyName: contact.anyName, about: contact.about))
        }
        else {
            if let json = json, let jsonData = json.data(using: .utf8, allowLossyConversion: false) {
                let decoder = JSONDecoder()
                if let nEvent = try? decoder.decode(NEvent.self, from: jsonData) {
                    guard let metaData = try? decoder.decode(NSetMetadata.self, from: nEvent.content.data(using: .utf8, allowLossyConversion: false)!) else {
                        return
                    }
    
                    let contact = Contact(context: DataProvider.shared().viewContext)
                    contact.pubkey = pubkey
                    contact.name = metaData.name
                    contact.display_name = metaData.display_name
                    contact.about = metaData.about
                    contact.picture = metaData.picture
                    contact.banner = metaData.banner
                    contact.nip05 = metaData.nip05
                    contact.lud16 = metaData.lud16
                    contact.lud06 = metaData.lud06
                    contact.metadata_created_at = Int64(nEvent.createdAt.timestamp) // by author kind 0
                    contact.updated_at = Int64(Date.now.timeIntervalSince1970) // by Nostur
                    
                    if contact.anyName != contact.authorKey { // For showing "Previously known as"
                        contact.fixedName = contact.anyName
                    }
//                    Kind0Processor.shared.receive.send(Profile(pubkey: contact.pubkey, name: contact.anyName, pictureUrl: contact.pictureUrl))
//                    EventRelationsQueue.shared.addAwaitingContact(contact)
//                    Contact.updateRelatedEvents(contact)
//                    Contact.updateRelatedAccounts(contact)
                    
//                    self.contact = contact
                    self.viewState = .readyContact(ContactInfo(pubkey: contact.pubkey, pictureUrl: contact.pictureUrl, anyName: contact.anyName, about: contact.about))
                }
            }
            else { // missing json, so fetch from relays
                self.backlog = Backlog(timeout: 8.0, auto: true)
                let reqTask = ReqTask(
                    debounceTime: 1.0,
                    reqCommand: { taskId in
                        req(RM.getUserMetadata(pubkey: pubkey, subscriptionId: taskId))
                    },
                    processResponseCommand: { taskId, relayMessage, event in
                        if let contact = Contact.fetchByPubkey(pubkey, context: DataProvider.shared().viewContext) {
//                            self.contact = contact
                            self.viewState = .readyContact(ContactInfo(pubkey: contact.pubkey, pictureUrl: contact.pictureUrl, anyName: contact.anyName, about: contact.about))
                        }
                        self.backlog?.clear()
                        pn.json = event?.toNEvent().eventJson()
                    },
                    timeoutCommand: { taskId in
                        self.viewState = .error("Could not find contact")
                        self.backlog?.clear()
                    })

                self.backlog?.add(reqTask)
                reqTask.fetch()
                
            }
        }
    }
    
}


struct BookmarksCountPreferenceKeyx: PreferenceKey {
    static var defaultValue: String = ""
    
    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}
struct PrivateNotesCountPreferenceKeyx: PreferenceKey {
    static var defaultValue: String = ""
    
    static func reduce(value: inout String, nextValue: () -> String) {
        value = nextValue()
    }
}
