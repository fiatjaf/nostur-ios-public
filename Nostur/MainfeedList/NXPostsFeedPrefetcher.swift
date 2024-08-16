//
//  NXPostsFeedPrefetcher.swift
//  Nostur
//
//  Created by Fabian Lachman on 03/08/2024.
//

import Foundation
import UIKit
import Nuke

class NXPostsFeedPrefetcher: NSObject, UICollectionViewDataSourcePrefetching {
        
    weak var columnViewModel: NXColumnViewModel?
    
    func collectionView(_: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let columnViewModel, case .posts(let nrPosts) = columnViewModel.viewState else {
            return
        }
        
        let postsForIndexPaths = indexPaths.compactMap { nrPosts[safe: $0.row] }
        guard !postsForIndexPaths.isEmpty else { return }
        
        bg().perform { [weak columnViewModel] in
            guard let columnViewModel, let availableWidth = columnViewModel.availableWidth else { return }
            
            var imageRequests: [ImageRequest] = []
            var imageRequestsPFP: [ImageRequest] = []
            
            for item in postsForIndexPaths {
                if !item.missingPs.isEmpty {
                    QueuedFetcher.shared.enqueue(pTags: item.missingPs)
                    L.fetching.debug("🟠🟠 Prefetcher: \(item.missingPs.count) missing contacts (event.pubkey or event.pTags) for: \(item.id)")
                }
                
                // Everything below here is image or link preview fetching, skip if low data mode
                guard !SettingsStore.shared.lowDataMode else { continue }
                
                if let pictureUrl = item.contact?.pictureUrl, pictureUrl.absoluteString.prefix(7) != "http://" {
                    imageRequestsPFP.append(pfpImageRequestFor(pictureUrl, size: DIMENSIONS.POST_ROW_PFP_DIAMETER))
                }
                
                imageRequestsPFP.append(contentsOf: item
                    .parentPosts
                    .compactMap { $0.contact?.pictureUrl }
                    .filter { $0.absoluteString.prefix(7) != "http://" }
                    .map { pfpImageRequestFor($0, size: DIMENSIONS.POST_ROW_PFP_DIAMETER) }
                )
                
                for element in item.contentElements {
                    switch element {
                    case .image(let mediaContent):
                        if mediaContent.url.absoluteString.prefix(7) == "http://" { continue }
                        // SHOULD BE SAME AS IN ContentRenderer:
                        if let dimensions = mediaContent.dimensions {
                            let scaledDimensions = Nostur.scaledToFit(dimensions, scale: UIScreen.main.scale, maxWidth: dimensions.width, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                            
                            // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                            imageRequests.append(makeImageRequest(mediaContent.url, width: scaledDimensions.width, height: scaledDimensions.height, label: "prefetch"))
                        }
                        else {
                            // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                            imageRequests.append(makeImageRequest(mediaContent.url, width: availableWidth, height: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, label: "prefetch (unscaled)"))
                        }
                    default:
                        continue
                    }
                }
                
                // TODO: do parent posts if replies is enabled (PostOrThread)
                //                for parentPost in item.parentPosts {
                //                    // Same as above
                //                    // for element in parentPost.contentElements { }
                //                }
                
                for url in item.linkPreviewURLs.filter({ $0.absoluteString.prefix(7) != "http://" }) {
                    fetchMetaTags(url: url) { result in
                        do {
                            let tags = try result.get()
                            LinkPreviewCache.shared.cache.setObject(for: url, value: tags)
                            L.og.debug("✓✓ Loaded link preview meta tags from \(url)")
                        }
                        catch { }
                    }
                }
            }
            
            guard !SettingsStore.shared.lowDataMode else { return }
            L.og.debug("☘️☘️ Prefetching \(imageRequests.count) + \(imageRequestsPFP.count)")
            if !imageRequests.isEmpty {
                ImageProcessing.shared.contentPrefetcher.startPrefetching(with: imageRequests)
            }
            if !imageRequestsPFP.isEmpty {
                ImageProcessing.shared.pfpPrefetcher.startPrefetching(with: imageRequestsPFP)
            }
        }
    }
    
    func collectionView(_: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        guard let columnViewModel, case .posts(let nrPosts) = columnViewModel.viewState else {
            return
        }
        
        let postsForIndexPaths = indexPaths.compactMap { nrPosts[safe: $0.row] }
        guard !postsForIndexPaths.isEmpty else { return }
        
        bg().perform { [weak columnViewModel] in
            guard let columnViewModel, let availableWidth = columnViewModel.availableWidth else { return }
            
            var imageRequests: [ImageRequest] = []
            var imageRequestsPFP: [ImageRequest] = []
            
            for item in postsForIndexPaths {
                
                if !item.missingPs.isEmpty {
                    QueuedFetcher.shared.dequeue(pTags: item.missingPs)
                }
                
                // Everything below here is image or link preview fetching, skip if low data mode
                guard !SettingsStore.shared.lowDataMode else { continue }
                
                if let pictureUrl = item.contact?.pictureUrl, pictureUrl.absoluteString.prefix(7) != "http://" {
                    imageRequestsPFP.append(pfpImageRequestFor(pictureUrl, size: DIMENSIONS.POST_ROW_PFP_DIAMETER))
                }
                
                imageRequestsPFP.append(contentsOf: item
                    .parentPosts
                    .compactMap { $0.contact?.pictureUrl }
                    .filter { $0.absoluteString.prefix(7) != "http://" }
                    .map { pfpImageRequestFor($0, size: DIMENSIONS.POST_ROW_PFP_DIAMETER) }
                )
                
                for element in item.contentElements {
                    switch element {
                    case .image(let mediaContent):
                        if mediaContent.url.absoluteString.prefix(7) == "http://" { continue }
                        // SHOULD BE SAME AS IN ContentRenderer:
                        if let dimensions = mediaContent.dimensions {
                            let scaledDimensions = Nostur.scaledToFit(dimensions, scale: UIScreen.main.scale, maxWidth: dimensions.width, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                            
                            
                            // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                            imageRequests.append(makeImageRequest(mediaContent.url, width: scaledDimensions.width, height: scaledDimensions.height, label: "cancel prefetch"))
                        }
                        else {
                            // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                            imageRequests.append(makeImageRequest(mediaContent.url, width: availableWidth, height: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, label: "cancel prefetch (unscaled)"))
                        }
                    default:
                        continue
                    }
                }
                
                // TODO: do parent posts if replies is enabled (PostOrThread)
                //                for parentPost in item.parentPosts {
                //                    // Same as above
                //                    // for element in parentPost.contentElements { }
                //                }
            }
            
            guard !SettingsStore.shared.lowDataMode else { return }
            if !imageRequests.isEmpty {
                ImageProcessing.shared.contentPrefetcher.stopPrefetching(with: imageRequests)
            }
            if !imageRequestsPFP.isEmpty {
                ImageProcessing.shared.pfpPrefetcher.stopPrefetching(with: imageRequestsPFP)
            }
        }
    }
}


class NXPostsFeedTablePrefetcher: NSObject, UITableViewDataSourcePrefetching {
        
    weak var columnViewModel: NXColumnViewModel?
    
    func tableView(_: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        guard let columnViewModel, case .posts(let nrPosts) = columnViewModel.viewState else {
            return
        }
        
        let postsForIndexPaths = indexPaths.compactMap { nrPosts[safe: $0.row] }
        guard !postsForIndexPaths.isEmpty else { return }
        
        bg().perform { [weak columnViewModel] in
            guard let columnViewModel, let availableWidth = columnViewModel.availableWidth else { return }
            
            var imageRequests: [ImageRequest] = []
            var imageRequestsPFP: [ImageRequest] = []
            
            for item in postsForIndexPaths {
                if !item.missingPs.isEmpty {
                    QueuedFetcher.shared.enqueue(pTags: item.missingPs)
                    L.fetching.debug("🟠🟠 Prefetcher: \(item.missingPs.count) missing contacts (event.pubkey or event.pTags) for: \(item.id)")
                }
                
                // Everything below here is image or link preview fetching, skip if low data mode
                guard !SettingsStore.shared.lowDataMode else { continue }
                
                if let pictureUrl = item.contact?.pictureUrl, pictureUrl.absoluteString.prefix(7) != "http://" {
                    imageRequestsPFP.append(pfpImageRequestFor(pictureUrl, size: DIMENSIONS.POST_ROW_PFP_DIAMETER))
                }
                
                imageRequestsPFP.append(contentsOf: item
                    .parentPosts
                    .compactMap { $0.contact?.pictureUrl }
                    .filter { $0.absoluteString.prefix(7) != "http://" }
                    .map { pfpImageRequestFor($0, size: DIMENSIONS.POST_ROW_PFP_DIAMETER) }
                )
                
                for element in item.contentElements {
                    switch element {
                    case .image(let mediaContent):
                        if mediaContent.url.absoluteString.prefix(7) == "http://" { continue }
                        // SHOULD BE SAME AS IN ContentRenderer:
                        if let dimensions = mediaContent.dimensions {
                            let scaledDimensions = Nostur.scaledToFit(dimensions, scale: UIScreen.main.scale, maxWidth: dimensions.width, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                            
                            // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                            imageRequests.append(makeImageRequest(mediaContent.url, width: scaledDimensions.width, height: scaledDimensions.height, label: "prefetch"))
                        }
                        else {
                            // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                            imageRequests.append(makeImageRequest(mediaContent.url, width: availableWidth, height: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, label: "prefetch (unscaled)"))
                        }
                    default:
                        continue
                    }
                }
                
                // TODO: do parent posts if replies is enabled (PostOrThread)
                //                for parentPost in item.parentPosts {
                //                    // Same as above
                //                    // for element in parentPost.contentElements { }
                //                }
                
                for url in item.linkPreviewURLs.filter({ $0.absoluteString.prefix(7) != "http://" }) {
                    fetchMetaTags(url: url) { result in
                        do {
                            let tags = try result.get()
                            LinkPreviewCache.shared.cache.setObject(for: url, value: tags)
                            L.og.debug("✓✓ Loaded link preview meta tags from \(url)")
                        }
                        catch { }
                    }
                }
            }
            
            guard !SettingsStore.shared.lowDataMode else { return }
            L.og.debug("☘️☘️ Prefetching \(imageRequests.count) + \(imageRequestsPFP.count)")
            if !imageRequests.isEmpty {
                ImageProcessing.shared.contentPrefetcher.startPrefetching(with: imageRequests)
            }
            if !imageRequestsPFP.isEmpty {
                ImageProcessing.shared.pfpPrefetcher.startPrefetching(with: imageRequestsPFP)
            }
        }
    }
    
    func tableView(_: UITableView, cancelPrefetchingForRowsAt indexPaths: [IndexPath]) {
        guard let columnViewModel, case .posts(let nrPosts) = columnViewModel.viewState else {
            return
        }
        
        let postsForIndexPaths = indexPaths.compactMap { nrPosts[safe: $0.row] }
        guard !postsForIndexPaths.isEmpty else { return }
        
        bg().perform { [weak columnViewModel] in
            guard let columnViewModel, let availableWidth = columnViewModel.availableWidth else { return }
            
            var imageRequests: [ImageRequest] = []
            var imageRequestsPFP: [ImageRequest] = []
            
            for item in postsForIndexPaths {
                
                if !item.missingPs.isEmpty {
                    QueuedFetcher.shared.dequeue(pTags: item.missingPs)
                }
                
                // Everything below here is image or link preview fetching, skip if low data mode
                guard !SettingsStore.shared.lowDataMode else { continue }
                
                if let pictureUrl = item.contact?.pictureUrl, pictureUrl.absoluteString.prefix(7) != "http://" {
                    imageRequestsPFP.append(pfpImageRequestFor(pictureUrl, size: DIMENSIONS.POST_ROW_PFP_DIAMETER))
                }
                
                imageRequestsPFP.append(contentsOf: item
                    .parentPosts
                    .compactMap { $0.contact?.pictureUrl }
                    .filter { $0.absoluteString.prefix(7) != "http://" }
                    .map { pfpImageRequestFor($0, size: DIMENSIONS.POST_ROW_PFP_DIAMETER) }
                )
                
                for element in item.contentElements {
                    switch element {
                    case .image(let mediaContent):
                        if mediaContent.url.absoluteString.prefix(7) == "http://" { continue }
                        // SHOULD BE SAME AS IN ContentRenderer:
                        if let dimensions = mediaContent.dimensions {
                            let scaledDimensions = Nostur.scaledToFit(dimensions, scale: UIScreen.main.scale, maxWidth: dimensions.width, maxHeight: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT)
                            
                            
                            // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                            imageRequests.append(makeImageRequest(mediaContent.url, width: scaledDimensions.width, height: scaledDimensions.height, label: "cancel prefetch"))
                        }
                        else {
                            // SHOULD BE EXACT SAME PARAMS AS IN SingleMediaViewer!!
                            imageRequests.append(makeImageRequest(mediaContent.url, width: availableWidth, height: DIMENSIONS.MAX_MEDIA_ROW_HEIGHT, label: "cancel prefetch (unscaled)"))
                        }
                    default:
                        continue
                    }
                }
                
                // TODO: do parent posts if replies is enabled (PostOrThread)
                //                for parentPost in item.parentPosts {
                //                    // Same as above
                //                    // for element in parentPost.contentElements { }
                //                }
            }
            
            guard !SettingsStore.shared.lowDataMode else { return }
            if !imageRequests.isEmpty {
                ImageProcessing.shared.contentPrefetcher.stopPrefetching(with: imageRequests)
            }
            if !imageRequestsPFP.isEmpty {
                ImageProcessing.shared.pfpPrefetcher.stopPrefetching(with: imageRequestsPFP)
            }
        }
    }
}