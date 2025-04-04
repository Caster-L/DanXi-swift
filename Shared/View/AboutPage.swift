import SwiftUI
import CryptoKit
import ViewUtils

struct AboutPage: View {
    @AppStorage("debug-unlocked") private var debugUnlocked = false
    
    private var version: String {
        Bundle.main.releaseVersionNumber ?? ""
    }
    
    private var build: String {
        Bundle.main.buildVersionNumber ?? ""
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack {
                List {
                    Section {
                        LinkView(url: "https://danxi.fduhole.com", text: "Website", icon: "safari")
                        LinkView(url: "https://danxi.fduhole.com/doc/app-terms-and-condition", text: "Terms and Conditions", icon: "info.circle")
                        LinkView(url: "https://apps.apple.com/app/id1568629997?action=write-review", text: "Write a Review", icon: "star")
                        
                        DetailLink(value: SettingsSection.credit, replace: false) {
                            Label("Acknowledgements", systemImage: "heart")
                                .navigationStyle()
                        }
                    } header: {
                        GateKeeper {
                            appIcon
                                .textCase(.none)
                        }
                    }
                    
                    if debugUnlocked {
                        Section {
                            DetailLink(value: SettingsSection.debug, replace: false) {
                                Label("Debug", systemImage: "ant.circle.fill")
                                    .navigationStyle()
                            }
                        }
                    }
                }
            }
            
            #if os(iOS)
            VStack {
                Text(verbatim: "Copyright © 2024-2025 DanXi-Dev")
                Link(destination: URL(string: "https://beian.miit.gov.cn/")!) {
                    Text(verbatim: "沪ICP备2021032046号-4A")
                }
            }
            .foregroundStyle(.secondary)
            .font(.footnote)
            .padding()
            #endif
        }
        .labelStyle(.titleOnly)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .background(.systemGroupedBackground)
    }
    
    private var appIcon: some View {
        HStack {
            Spacer()
            VStack {
                Image("Icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                Text("DanXi")
                    .font(.title)
                    .bold()
                Text("Version \(version) (\(build))")
                    .font(.callout)
            }
            .padding(.bottom)
            Spacer()
        }
    }
}

/// The debug page is protected, only those who have the app password can access. The password is checked against a hash encryption.
struct GateKeeper<Content: View>: View {
    @AppStorage("debug-unlocked") private var debugUnlocked = false
    @AppStorage("watermark-unlocked") private var watermarkUnlocked = false
    @State private var tappedCount = 0
    
    private let normalCapabilityHash = "2a71f797c0c5b266e885fb8f9a137936aba75e9a9d9e9fca747f965452b35463"
    private let raisedCapabilityHash = "37ef71a680d30c47888856527c064cd02755ceeac2ef33e51c2e02d7bf93c089"
    
    let content: () -> Content
    
    /// Check password against hash encryption and grant user certain debug capability.
    private func checkPassword() {
        guard UIPasteboard.general.hasStrings,
              let password = UIPasteboard.general.string else { return }
        
        let hash = SHA256.hash(data: password.data(using: .utf8)!)
        let hashString = hash.map { String(format: "%02hhx", $0) }.joined()
        if hashString == normalCapabilityHash || hashString == raisedCapabilityHash {
            withAnimation {
                debugUnlocked = true
            }
        }
        
        if hashString == raisedCapabilityHash {
            watermarkUnlocked = true
        }
    }
    
    var body: some View {
        content()
            .onTapGesture {
                tappedCount += 1
                if tappedCount > 5 && !debugUnlocked {
                    checkPassword()
                }
            }
    }
}

struct LinkView: View {
    let url: String
    let text: LocalizedStringKey
    let icon: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Label {
                    Text(text)
                        .foregroundColor(.primary)
                } icon: {
                    Image(systemName: icon)
                }
                Spacer()
                Image(systemName: "link")
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AboutPage()
    }
}
