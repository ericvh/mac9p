import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Mac9P FSKit")
                .font(.title)
            Text("The filesystem lives in the extension target.")
                .foregroundStyle(.secondary)
            Text("Enable it in Settings → Login Items & Extensions → File System Extensions.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 180)
    }
}

