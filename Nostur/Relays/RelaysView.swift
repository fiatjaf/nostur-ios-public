//
//  RelaysView.swift
//  Nostur
//
//  Created by Fabian Lachman on 08/01/2023.
//

import SwiftUI
import CoreData

struct RelayRowView: View {
    @ObservedObject var relay:Relay
    @ObservedObject private var cp:ConnectionPool = .shared
    
    var isConnected:Bool {
        connection?.isConnected ?? false
    }
    
    @State var connection:RelayConnection? = nil
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        HStack {
            if (isConnected) {
                Image(systemName: "circle.fill").foregroundColor(.green)
                    .opacity(1.0)
            }
            else {
                Image(systemName: "circle.fill")
                    .foregroundColor(.gray)
                    .opacity(0.2)
            }
            
            Text("\(relay.url ?? "(Unknown)")")
            
            Spacer()
            
            Image(systemName:"arrow.down.circle.fill").foregroundColor(relay.read ? .green : .gray)
                .opacity(relay.read ? 1.0 : 0.2)
                .onTapGesture {
                    relay.read.toggle()
                    connection?.relayData.setRead(relay.read)
                    if relay.read {
                        connection?.connect(forceConnectionAttempt: true)
                    }
                    DataProvider.shared().save()
                }
            
            Image(systemName:"arrow.up.circle.fill").foregroundColor(relay.write ? .green : .gray)
                .opacity(relay.write ? 1.0 : 0.2)
                .onTapGesture {
                    relay.write.toggle()
                    connection?.relayData.setWrite(relay.write)
                    DataProvider.shared().save()
                }
        }
        .task {
            let relayUrl = relay.url ?? ""
            connection = ConnectionPool.shared.connectionByUrl(relayUrl.lowercased())
            print("connection is now \(connection?.url ?? "")")
        }
        .onReceive(cp.objectWillChange, perform: { _ in
            let relayUrl = relay.url ?? ""
            connection = ConnectionPool.shared.connectionByUrl(relayUrl.lowercased())
            print("connection is now \(connection?.url ?? "")")
        })
    }
}

struct RelaysView: View {
    @EnvironmentObject private var themes:Themes
    @State var createRelayPresented = false
    @State var editRelay:Relay?

    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [SortDescriptor(\Relay.createdAt, order: .forward)],
        animation: .default)
    var relays: FetchedResults<Relay>

    var body: some View {
        VStack {
            ForEach(relays, id:\.objectID) { relay in
                RelayRowView(relay: relay)
                    .onTapGesture {
                        editRelay = relay
                    }
                Divider()
            }
        }
        .sheet(item: $editRelay, content: { relay in
            NavigationStack {
                RelayEditView(relay: relay)
            }
            .presentationBackground(themes.theme.background)
        })
    }    
}

struct RelaysView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadRelays()
        }) {
            NavigationStack {
                RelaysView()
                    .padding()
            }
        }
    }
}
