import SwiftUI

struct CompatibilityPane: View {
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var detector: ToolchainDetector
    @State private var isShowingCreateSheet = false
    @State private var isShowingRuntimeManager = false

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedBottleID) {
                Section("Bottles") {
                    if store.bottles.isEmpty {
                        Text("No bottles yet. Bottles are created automatically when you install a game from your Library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.bottles) { bottle in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bottle.name).lineLimit(1)
                                Text(bottle.runtimeLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: bottle.steamAppID != nil ? "gamecontroller.fill" : "shippingbox")
                        }
                        .tag(bottle.id)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    RuntimeSummaryView()
                    Button {
                        isShowingRuntimeManager = true
                    } label: {
                        Label("Runtime Manager", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        isShowingCreateSheet = true
                    } label: {
                        Label("New Manual Bottle", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .frame(minWidth: 240)
            .toolbar {
                Button {
                    Task { await detector.refresh() }
                } label: {
                    Label("Refresh Runtimes", systemImage: "arrow.clockwise")
                }
                .disabled(detector.isRefreshing)
            }
        } detail: {
            if let bottle = store.selectedBottle {
                BottleDetailView(bottle: bottle)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "wineglass").font(.system(size: 56)).foregroundStyle(.secondary)
                    Text("Compatibility").font(.title2.bold())
                    Text("This is where Wine prefixes ('bottles') live. Select a bottle on the left to see its runtime, graphics backend, launch args, and logs.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateBottleView()
        }
        .sheet(isPresented: $isShowingRuntimeManager) {
            RuntimeManagerView()
        }
    }
}


