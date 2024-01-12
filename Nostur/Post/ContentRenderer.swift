//
//  ContentRenderer.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/03/2023.
//

import SwiftUI
import Nuke
import NukeUI
import Combine

// Renders embeds (VIEWS), not links (in TEXT)
struct ContentRenderer: View { // VIEW things
    private var theme:Theme
    private let nrPost:NRPost
    private let isDetail:Bool
    private let fullWidth:Bool
    private let availableWidth:CGFloat
    private let contentElements:[ContentElement]
    private let forceAutoload:Bool
    @Binding var didStart:Bool
    
    init(nrPost: NRPost, isDetail:Bool = false, fullWidth:Bool = false, availableWidth:CGFloat, forceAutoload: Bool = false, theme:Theme, didStart: Binding<Bool> = .constant(false)) {
        self.isDetail = isDetail
        self.nrPost = nrPost
        self.fullWidth = fullWidth
        self.availableWidth = availableWidth
        self.contentElements = isDetail ? nrPost.contentElementsDetail : nrPost.contentElements
        self.forceAutoload = forceAutoload
        self.theme = theme
        _didStart = didStart
    }
    
    private var shouldAutoload:Bool {
        forceAutoload || SettingsStore.shouldAutodownload(nrPost)
    }
    
    var body: some View {
        VStack(alignment:.leading, spacing: 0) {
            ForEach(contentElements.indices, id:\.self) { index in
                switch contentElements[index] {
                case .nrPost(let nrPost):
                    EmbeddedPost(nrPost, forceAutoload: shouldAutoload, theme: theme)
//                        .frame(minHeight: 75)
                        .environmentObject(DIMENSIONS.embeddedDim(availableWidth: availableWidth, isScreenshot: nrPost.isPreview))
                    //                        .fixedSize(horizontal: false, vertical: true)
//                        .debugDimensions("EmbeddedPost")
                        .padding(.vertical, 10)
                        .id(index)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                case .nevent1(let identifier):
                    NEventView(identifier: identifier, forceAutoload: shouldAutoload, theme: theme)
//                        .frame(minHeight: 75)
                        .environmentObject(DIMENSIONS.embeddedDim(availableWidth: availableWidth, isScreenshot: nrPost.isPreview))
//                        .debugDimensions("NEventView")
                        .padding(.vertical, 10)
                        .id(index)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                case .npub1(let npub):
                    if let pubkey = hex(npub) {
                        ProfileCardByPubkey(pubkey: pubkey, theme: theme)
                            .padding(.vertical, 10)
                            .id(index)
//                            .withoutAnimation()
//                            .transaction { t in t.animation = nil }
                    }
                    else {
                        EmptyView()
                            .id(index)
                    }
                case .nprofile1(let identifier):
                    NProfileView(identifier: identifier)
                        .id(index)
//                        .transaction { t in t.animation = nil }
                case .note1(let noteId):
                    if let noteHex = hex(noteId) {
                        EmbedById(id: noteHex, forceAutoload: shouldAutoload, theme: theme)
//                            .frame(minHeight: 75)
                            .environmentObject(DIMENSIONS.embeddedDim(availableWidth: availableWidth, isScreenshot: nrPost.isPreview))
//                            .debugDimensions("QuoteById.note1")
                            .padding(.vertical, 10)
//                            .withoutAnimation()
//                            .transaction { t in t.animation = nil }
                            .onTapGesture {
                                guard !isDetail else { return }
                                navigateTo(nrPost)
                            }
                            .id(index)
                    }
                    else {
                        EmptyView()
                            .id(index)
                    }
                case .noteHex(let hex):
                    EmbedById(id: hex, forceAutoload: shouldAutoload, theme: theme)
//                        .frame(minHeight: 75)
                        .environmentObject(DIMENSIONS.embeddedDim(availableWidth: availableWidth, isScreenshot: nrPost.isPreview))
//                        .debugDimensions("QuoteById.noteHex")
                        .padding(.vertical, 10)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                        .id(index)
                case .code(let code): // For text notes
                    Text(verbatim: code)
                        .font(.system(.body, design: .monospaced))
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                        .id(index)
                case .text(let attributedStringWithPs): // For text notes
                    NRContentTextRenderer(attributedStringWithPs: attributedStringWithPs, isDetail: isDetail, isPreview: nrPost.isPreview)
                        .equatable()
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                        .id(index)
                case .md(let markdownContentWithPs): // For long form articles
                    NRContentMarkdownRenderer(markdownContentWithPs: markdownContentWithPs, theme: theme, maxWidth: availableWidth)
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                        .id(index)
                case .lnbc(let text):
                    LightningInvoice(invoice: text, theme: theme)
                        .padding(.vertical, 10)
                        .id(index)
                case .cashu(let text):
                    CashuTokenView(token: text, theme: theme)
                        .padding(.vertical, 10)
                        .id(index)
                case .video(let mediaContent):
                    if let dimensions = mediaContent.dimensions {
                        // for video, dimensions are points not pixels? Scale set to 1.0 always
                        let scaledDimensions = Nostur.scaledToFit(dimensions, scale: 1.0, maxWidth: availableWidth, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                        
#if DEBUG
                        //                        Text(".video.availableWidth (SD): \(Int(availableWidth))\ndim:\(dimensions.debugDescription)\nSD: \(scaledDimensions.debugDescription)")
                        //                            .frame(maxWidth: .infinity)
                        //                            .background(.red)
                        //                            .foregroundColor(.white)
                        //                            .debugDimensions()
#endif
                        
                        NosturVideoViewur(url: mediaContent.url, pubkey: nrPost.pubkey, height:scaledDimensions.height, videoWidth: availableWidth, autoload: shouldAutoload, fullWidth: fullWidth, contentPadding: nrPost.kind == 30023 ? 10 : 0, theme: theme, didStart: $didStart)
                        //                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: scaledDimensions.width, height: scaledDimensions.height)
//                            .debugDimensions("sd.video")
                            .background {
                                if SettingsStore.shared.lowDataMode {
                                    theme.lineColor.opacity(0.2)
                                }
                            }
                            .padding(.horizontal, fullWidth ? -10 : 0)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: SettingsStore.shared.lowDataMode ? .leading : .center)
                            .id(index)
//                            .withoutAnimation()
//                            .transaction { t in t.animation = nil }
                    }
                    else {
                        
#if DEBUG
                        //                        Text(".video.availableWidth: \(Int(availableWidth))")
                        //                            .frame(maxWidth: .infinity)
                        //                            .background(.red)
                        //                            .foregroundColor(.white)
                        //                            .debugDimensions()
#endif
                        
                        NosturVideoViewur(url: mediaContent.url, pubkey: nrPost.pubkey, videoWidth: availableWidth, autoload: shouldAutoload, fullWidth: fullWidth, contentPadding: nrPost.kind == 30023 ? 10 : 0, theme: theme, didStart: $didStart)
//                            .debugDimensions("video")
                        //                            .frame(maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                            .padding(.horizontal, fullWidth ? -10 : 0)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: SettingsStore.shared.lowDataMode ? .leading : .center)
                            .id(index)
//                            .withoutAnimation()
//                            .transaction { t in t.animation = nil }
                    }
                    
                case .image(let mediaContent):
                    if let dimensions = mediaContent.dimensions {
                        let scaledDimensions = Nostur.scaledToFit(dimensions, scale: UIScreen.main.scale, maxWidth: availableWidth, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                        
#if DEBUG
                        //                        Text(".image.availableWidth (SD): \(Int(availableWidth))\ndim:\(dimensions.debugDescription)\nSD: \(scaledDimensions.debugDescription)")
                        //                            .frame(maxWidth: .infinity)
                        //                            .background(.red)
                        //                            .foregroundColor(.white)
                        //                            .debugDimensions()
#endif
                        
                        SingleMediaViewer(url: mediaContent.url, pubkey: nrPost.pubkey, height:scaledDimensions.height, imageWidth: availableWidth, fullWidth: fullWidth, autoload: shouldAutoload, contentPadding: nrPost.kind == 30023 ? 10 : 0, theme: theme, scaledDimensions: scaledDimensions, imageUrls: nrPost.imageUrls)
                        //                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: max(25, scaledDimensions.width), height: max(25,scaledDimensions.height))
//                            .debugDimensions("sd.image \(scaledDimensions.width)x\(scaledDimensions.height)")
                            .background {
                                if SettingsStore.shared.lowDataMode {
                                    theme.lineColor.opacity(0.2)
                                }
                            }
                            .padding(.horizontal, fullWidth ? -10 : 0)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: SettingsStore.shared.lowDataMode ? .leading : .center)
                            .id(index)
//                            .withoutAnimation()
//                            .transaction { t in t.animation = nil }
                    }
                    else {
                        
#if DEBUG
                        //                        Text(".image.availableWidth: \(Int(availableWidth))")
                        //                            .frame(maxWidth: .infinity)
                        //                            .background(.red)
                        //                            .foregroundColor(.white)
                        //                            .debugDimensions()
#endif
                        
                        SingleMediaViewer(url: mediaContent.url, pubkey: nrPost.pubkey, height:DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, imageWidth: availableWidth, fullWidth: fullWidth, autoload: shouldAutoload, contentPadding: nrPost.kind == 30023 ? 10 : 0, theme: theme, imageUrls: nrPost.imageUrls)
//                            .debugDimensions("image")
                            .padding(.horizontal, fullWidth ? -10 : 0)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: SettingsStore.shared.lowDataMode ? .leading : .center)
//                            .debugDimensions("image.frame")
                            .id(index)
//                            .background(Color.yellow)
//                            .withoutAnimation()
//                            .transaction { t in t.animation = nil }
                    }
                case .linkPreview(let url):
                    LinkPreviewView(url: url, autoload: shouldAutoload, theme: theme)
                        .padding(.vertical, 10)
                        .id(index)
//                        .withoutAnimation()
//                        .transaction { t in t.animation = nil }
                case .postPreviewImage(let postedImageMeta):
                    Image(uiImage: postedImageMeta.imageData)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 600)
                        .padding(.top, 10)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .id(index)
                default:
                    EmptyView()
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                        .id(index)
                }
            }
        }
        .animation(.none)
//        .transaction { t in
//            t.animation = nil
//        }
    }
}

#Preview("Content Renderer 1") {
    let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
    return PreviewContainer({ pe in
//        pe.loadContacts()
//        pe.loadPosts()
        pe.loadMedia()
        pe.parseMessages([
            ###"["EVENT","1",{"pubkey":"9989500413fb756d8437912cc32be0730dbe1bfc6b5d2eef759e1456c239f905","content":"Watch out for the Jazz attack, be glad your not a squirrel 🐿️ https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov ","id":"473f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879","created_at":1692538971,"sig":"0b6d7640814bd5f4b39c4d4cd72ceebaf380775e0682f4667fa7e97a925223bb2f495ba59304485518f55761d29f8abeea8727595ad2fa5f9ad5c5b26ec962eb","kind":1,"tags":[["e","0ffa41f84eb1e66b3b10b8b3f91f55fcca67d46995236568ac22bba2433b397d"],["e","013b859a0dba4ae29a35a19a4cd5ae27b30311537325c9d9e83ef996e2e36968"],["p","0155373ac79b7ffb0f586c3e68396f9e82d46f7afe7016d46ed9ca46ba3e1bed"],["p","e844b39d850acbb13bba1a20057250fe6b3deff5f1ecc95b6a99dc35adafb6a2"],["imeta","url https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov","blurhash eVE:nYtOaxoeof4fWFbGj[j[Nra#ofkBWBXft5j[a#axaQbHj?a#of","dim 720x1280"]]}]"###])
    }) {
        SmoothListMock {
            if let nrPost = PreviewFetcher.fetchNRPost("473f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879") {
                Box {
                    ContentRenderer(nrPost: nrPost, availableWidth: UIScreen.main.bounds.width, theme: Themes.default.theme)
                }
            }
        }
    }
}

#Preview("Content Renderer  2") {
    let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadMedia()
        pe.parseMessages([
            ###"["EVENT","1",{"pubkey":"9989500413fb756d8437912cc32be0730dbe1bfc6b5d2eef759e1456c239f905","content":"Watch out for the Jazz attack, be glad your not a squirrel 🐿️ https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov ","id":"473f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879","created_at":1692538971,"sig":"0b6d7640814bd5f4b39c4d4cd72ceebaf380775e0682f4667fa7e97a925223bb2f495ba59304485518f55761d29f8abeea8727595ad2fa5f9ad5c5b26ec962eb","kind":1,"tags":[["e","0ffa41f84eb1e66b3b10b8b3f91f55fcca67d46995236568ac22bba2433b397d"],["e","013b859a0dba4ae29a35a19a4cd5ae27b30311537325c9d9e83ef996e2e36968"],["p","0155373ac79b7ffb0f586c3e68396f9e82d46f7afe7016d46ed9ca46ba3e1bed"],["p","e844b39d850acbb13bba1a20057250fe6b3deff5f1ecc95b6a99dc35adafb6a2"],["imeta","url https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov","blurhash eVE:nYtOaxoeof4fWFbGj[j[Nra#ofkBWBXft5j[a#axaQbHj?a#of","dim 720x1280"]]}]"###])
    }) {
        SmoothListMock {
            if let nrPost = PreviewFetcher.fetchNRPost("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3") {
                Box {
                    ContentRenderer(nrPost: nrPost, availableWidth: UIScreen.main.bounds.width, theme: Themes.default.theme)
                }
            }
        }
    }
}

#Preview("Content Renderer 3") {
    let _ = ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
    return PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadMedia()
        pe.parseMessages([
            ###"["EVENT","1",{"pubkey":"9989500413fb756d8437912cc32be0730dbe1bfc6b5d2eef759e1456c239f905","content":"Watch out for the Jazz attack, be glad your not a squirrel 🐿️ https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov ","id":"473f85cb559d5d8866e7c3ffef536c67323ef44fe2d08d4bef42d82d9f868879","created_at":1692538971,"sig":"0b6d7640814bd5f4b39c4d4cd72ceebaf380775e0682f4667fa7e97a925223bb2f495ba59304485518f55761d29f8abeea8727595ad2fa5f9ad5c5b26ec962eb","kind":1,"tags":[["e","0ffa41f84eb1e66b3b10b8b3f91f55fcca67d46995236568ac22bba2433b397d"],["e","013b859a0dba4ae29a35a19a4cd5ae27b30311537325c9d9e83ef996e2e36968"],["p","0155373ac79b7ffb0f586c3e68396f9e82d46f7afe7016d46ed9ca46ba3e1bed"],["p","e844b39d850acbb13bba1a20057250fe6b3deff5f1ecc95b6a99dc35adafb6a2"],["imeta","url https://nostr.build/av/40cc2c4a2d33e3e082766765ec4f7cea1de8b442cae5b01cf779829762947a63.mov","blurhash eVE:nYtOaxoeof4fWFbGj[j[Nra#ofkBWBXft5j[a#axaQbHj?a#of","dim 720x1280"]]}]"###])
    }) {
        SmoothListMock {
            if let nrPost = PreviewFetcher.fetchNRPost("102177a51af895883e9256b70b2caff6b9ef90230359ee20f6dc7851ec9e5d5a") {
                Box {
                    ContentRenderer(nrPost: nrPost, availableWidth: UIScreen.main.bounds.width, theme: Themes.default.theme)
                }
            }
        }
    }
}


func scaledToFit(_ dimensions: CGSize, scale screenScale: Double, maxWidth: Double, maxHeight: Double) -> CGSize {
    let pointWidth = Double(dimensions.width / screenScale)
    let pointHeight = Double(dimensions.height / screenScale)
    
    let widthRatio = min(maxWidth / pointWidth,1)
    let heightRatio = min(maxHeight / pointHeight,1)
    let fittingScale = min(widthRatio, heightRatio)
    
    return CGSize(width: pointWidth * fittingScale, height: pointHeight * fittingScale)
}


struct EmbeddedPost: View {
    private let nrPost:NRPost
    @ObservedObject var prd:NRPost.PostRowDeletableAttributes
    private var forceAutoload:Bool
    private var theme:Theme
    
    init(_ nrPost:NRPost, forceAutoload:Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.prd = nrPost.postRowDeletableAttributes
        self.forceAutoload = forceAutoload
        self.theme = theme
    }
    
    var body: some View {
        if prd.blocked {
            HStack {
                Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) { nrPost.blocked = false }
                    .buttonStyle(.bordered)
            }
            .padding(.leading, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            .hCentered()
        }
        else if nrPost.kind == 30023 {
            ArticleView(nrPost, hideFooter: true, forceAutoload: forceAutoload, theme: theme)
                .padding(20)
                .background(
                    Color(.secondarySystemBackground)
                        .cornerRadius(15)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(.regularMaterial, lineWidth: 1)
                )
//                .debugDimensions("EmbeddedPost.ArticleView", alignment: .bottomLeading)
        }
        else {
            QuotedNoteFragmentView(nrPost: nrPost, forceAutoload: forceAutoload, theme: theme)
//                .debugDimensions("EmbeddedPost.QuotedNoteFragmentView", alignment: .bottomLeading)
        }
    }
}
