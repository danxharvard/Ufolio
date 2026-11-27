import SwiftUI
import CoreImage.CIFilterBuiltins

/// Send to iPhone: the page you're on, by AirDrop, through the Mac's Share menu, or as a QR code
/// your iPhone's camera can read. No account and no server: the QR code is made on your Mac,
/// only when you ask, and nothing runs in the background.
enum Beam {
    static func show(_ url: URL, title: String, in window: NSWindow?) {
        DialogHost.show(HushDialog(
            art: .symbol("iphone.and.arrow.forward"), theme: .hush, motion: .orbit,
            title: "Send to iPhone",
            message: title,
            detail: AnyView(BeamCard(url: url)),
            width: 340,
            choices: [.init(title: "Done", role: .primary)]), in: window)
    }

    /// A crisp QR code for the address, drawn on this Mac.
    static func qrCode(for url: URL, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Drawn once into a plain bitmap, one pixel per module (it's shown without smoothing):
        // a Core Image picture was redrawn by Core Image every time the card repainted.
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
    private static let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
}

private struct BeamCard: View {
    let url: URL
    @State private var qr: NSImage?
    @State private var tooLong = false
    /// Looked up once when the card opens (it was asked again every time the card redrew).
    @State private var airDrop = NSSharingService(named: .sendViaAirDrop)
    @State private var canAirDrop = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white)
                if let qr {
                    Image(nsImage: qr).interpolation(.none).resizable().frame(width: 168, height: 168)
                } else if tooLong {
                    // A very long address doesn't fit in a QR code (it used to spin for ever).
                    Text("This address is too long for a QR code. Use AirDrop or Share instead.")
                        .font(.system(size: 12)).foregroundStyle(.black.opacity(0.6)).multilineTextAlignment(.center).padding()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 192, height: 192)
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            Text("Point your iPhone’s camera at the code to open this page there.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                // Greyed out when AirDrop is off or unavailable (the button used to do nothing).
                Button {
                    airDrop?.perform(withItems: [url])
                } label: { Label("AirDrop", systemImage: "airplayaudio") }
                .disabled(!canAirDrop)
                ShareButton(url: url)
            }
            .controlSize(.large)
        }
        .padding(.top, 8)
        .task {
            canAirDrop = airDrop?.canPerform(withItems: [url]) ?? false
            // Made away from the main thread, so the card opens at once.
            let address = url
            let image = await Task.detached(priority: .userInitiated) { Beam.qrCode(for: address, size: 168) }.value
            qr = image
            tooLong = image == nil
        }
    }
}

/// The Mac's own Share menu (Messages, Mail, Notes, AirDrop…), opened from this button.
private struct ShareButton: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Share…", target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.url = url }
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    final class Coordinator: NSObject {
        var url: URL
        init(url: URL) { self.url = url }
        @objc func share(_ sender: NSButton) {
            NSSharingServicePicker(items: [url]).show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
    }
}
