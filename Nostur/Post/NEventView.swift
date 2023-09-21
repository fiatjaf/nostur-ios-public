//
//  NEventView.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/05/2023.
//

import SwiftUI

struct NEventView: View {
    @EnvironmentObject var theme:Theme
    let identifier:ShareableIdentifier
    @StateObject private var vm = FetchVM<NRPost>()
        
    var body: some View {
        Group {
            switch vm.state {
            case .initializing, .loading, .altLoading:
                ProgressView()
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .task {
                        guard let eventId = identifier.eventId else {
                            vm.error("Problem parsing nostr identifier")
                            return
                        }
                        vm.setFetchParams((
                            req: {
                                bg().perform { // 1. CHECK LOCAL DB
                                    if let event = try? Event.fetchEvent(id: eventId, context: bg()) {
                                        vm.ready(NRPost(event: event, withFooter: false))
                                    }
                                    else { // 2. ELSE CHECK RELAY
                                        req(RM.getEvent(id: eventId))
                                    }
                                }
                            },
                            onComplete: { relayMessage in
                                if let event = try? Event.fetchEvent(id: eventId, context: bg()) { // 3. WE FOUND IT ON RELAY
                                    if vm.state == .altLoading, let relay = identifier.relays.first {
                                        L.og.debug("Event found on using relay hint: \(eventId) - \(relay)")
                                    }
                                    vm.ready(NRPost(event: event, withFooter: false))
                                }
                                // Still don't have the event? try to fetch from relay hint
                                // TODO: Should try a relay we don't already have in our relay set
                                else if (vm.state == .loading) && identifier.relays.first != nil { // 4. TIMEOUT BUT WE TRY RELAY HINT
                                    vm.altFetch()
                                }
                                else { // 5. TIMEOUT
                                    vm.timeout()
                                }
                            },
                            altReq: { // IF WE HAVE A RELAY HINT WE USE THIS REQ, TRIGGERED BY vm.altFetch()
                                guard let relay = identifier.relays.first else { vm.timeout(); return }
                                EphemeralSocketPool.shared.sendMessage(RM.getEvent(id: eventId), relay: relay)
                            }
                            
                        ))
                        vm.fetch()
                    }
            case .ready(let nrPost):
                EmbeddedPost(nrPost)
            case .timeout:
                Text("Unable to fetch content")
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            case .error(let error):
                Text(error)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(theme.lineColor.opacity(0.2), lineWidth: 1)
        )
    }
}

struct NEventView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            NavigationStack {
                if let identifier = try? ShareableIdentifier("nevent1qqspg0h7quunckc8a7lxag0uvmpeewv9hx8cs3r9pmwsp77tqsfz3gcens7um") {
                    NEventView(identifier: identifier)
                }
            }
        }
    }
}
