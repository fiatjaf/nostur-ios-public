//
//  Kind1Default.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

// Note 1 default (not full-width)
struct Kind1Default: View {
    @EnvironmentObject var theme:Theme
    @EnvironmentObject var dim:DIMENSIONS
    let nrPost:NRPost
    @ObservedObject var pfpAttributes: NRPost.PFPAttributes
    let hideFooter:Bool // For rendering in NewReply
    let missingReplyTo:Bool // For rendering in thread
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    let isReply:Bool // is reply on PostDetail
    let isDetail:Bool
    let grouped:Bool
     
    let sp:SocketPool = .shared
    let up:Unpublisher = .shared
    @ObservedObject var settings:SettingsStore = .shared
    
    init(nrPost: NRPost, hideFooter:Bool = true, missingReplyTo:Bool = false, connect:ThreadConnectDirection? = nil, isReply:Bool = false, isDetail:Bool = false, grouped:Bool = false) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.isReply = isReply
        self.isDetail = isDetail
        self.grouped = grouped
    }
    
    let THREAD_LINE_OFFSET = 24.0
    
    var imageWidth:CGFloat {
        // FULL WIDTH IS OFF
        
        // LIST OR LIST PARENT
        if !isDetail { return dim.availableNoteRowImageWidth() }
        
        // DETAIL
        if isDetail && !isReply { return dim.availablePostDetailImageWidth() }
        
        // DETAIL PARENT OR REPLY
        return dim.availablePostDetailRowImageWidth()
    }
    
    @State var showMiniProfile = false
    
    var body: some View {
//        let _ = Self._printChanges()
        HStack(alignment: .top, spacing: 10) {
            ZappablePFP(pubkey: nrPost.pubkey, contact: pfpAttributes.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id)
                .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_HEIGHT)
                .background(alignment: .top) {
                    if connect == .top || connect == .both {
                        theme.lineColor
                            .opacity(0.2)
                            .frame(width: 2, height: 20)
                            .offset(x:0, y: -10)
                    }
                }
                .onTapGesture {
                    if !IS_APPLE_TYRANNY {
                        navigateTo(ContactPath(key: nrPost.pubkey))
                    }
                    else {
                        withAnimation {
                            showMiniProfile = true
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if (showMiniProfile) {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    sendNotification(.showMiniProfile,
                                                     MiniProfileSheetInfo(
                                                        pubkey: nrPost.pubkey,
                                                        contact: pfpAttributes.contact,
                                                        zapEtag: nrPost.id,
                                                        location: geo.frame(in: .global).origin
                                                     )
                                    )
                                    showMiniProfile = false
                                }
                        }
                          .frame(width: 10)
                          .zIndex(100)
                          .transition(.asymmetric(insertion: .scale(scale: 0.4), removal: .opacity))
                          .onReceive(receiveNotification(.dismissMiniProfile)) { _ in
                              showMiniProfile = false
                          }
                    }
                }
//                .transaction { transaction in
//                    transaction.animation = nil
//                }

            VStack(alignment:.leading, spacing: 3) { // Post container
                HStack(alignment: .top) { // name + reply + context menu
                    NoteHeaderView(nrPost: nrPost)
                    Spacer()
                    LazyNoteMenuButton(nrPost: nrPost)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 21.0)
//                .debugDimensions()
//                .transaction { transaction in
//                    transaction.animation = nil
//                }
                if missingReplyTo {
                    ReplyingToFragmentView(nrPost: nrPost)
                }
                if let fileMetadata = nrPost.fileMetadata {
                    Kind1063(nrPost, fileMetadata:fileMetadata, availableWidth: imageWidth)
//                        .transaction { transaction in
//                            transaction.animation = nil
//                        }
                }
                else {
                    if (nrPost.kind != 1) && (nrPost.kind != 6) {
                        Label(String(localized:"kind \(Double(nrPost.kind).clean) type not (yet) supported", comment: "Message shown when a 'kind X' post is not yet supported"), systemImage: "exclamationmark.triangle.fill")
                            .hCentered()
                            .frame(maxWidth: .infinity)
                            .background(theme.lineColor.opacity(0.2))
                    }
                    if let subject = nrPost.subject {
                        Text(subject)
                            .fontWeight(.bold)
                            .lineLimit(3)
                    }

                    ContentRenderer(nrPost: nrPost, isDetail:isDetail, fullWidth: false, availableWidth: imageWidth)
                        .fixedSize(horizontal: false, vertical: true) // TODO: TEST WITH/WITHOUT
                        .frame(maxWidth: .infinity, alignment:.leading)
//                        .transaction { transaction in
//                            transaction.animation = nil
//                            transaction.disablesAnimations = true
//                        }

                    if !isDetail && (nrPost.previewWeights?.moreItems ?? false) {
                        ReadMoreButton(nrPost: nrPost)
                            .padding(.vertical, 5)
                            .hCentered()
                    }
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    FooterFragmentView(nrPost: nrPost)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: isDetail ? 8800 : DIMENSIONS.POST_MAX_ROW_HEIGHT, alignment: .topLeading)
            .clipped()
        }
        .background(alignment: .leading) {
            if connect == .bottom || connect == .both {
                theme.lineColor
                    .frame(width: 2)
                    .opacity(0.2)
                    .offset(x: THREAD_LINE_OFFSET, y: 20)                
            }
        }        
    }
}

struct Kind1Default_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            SmoothListMock {
                if let nrPost = PreviewFetcher.fetchNRPost("da3f7863d634b2020f84f38bd3dac5980794715702e85c3f164e49ebe5dc98cc") {
                    Box {
                        Kind1Default(nrPost: nrPost)
                    }
                }
                
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    Box {
                        Kind1Default(nrPost: nrPost)
                    }
                }
            }
            .withSheets()
        }
    }
}
