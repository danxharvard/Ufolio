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
        let scale = (size * 2) / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }
}

private struct BeamCard: View {
    let url: URL
    @State private var qr: NSImage?
    @State private var tooLong = false

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
                let airDrop = NSSharingService(named: .sendViaAirDrop)
                Button {
                    airDrop?.perform(withItems: [url])
                } label: { Label("AirDrop", systemImage: "airplayaudio") }
                .disabled(!(airDrop?.canPerform(withItems: [url]) ?? false))
                ShareButton(url: url)
            }
            .controlSize(.large)
        }
        .padding(.top, 8)
        .task {
            qr = Beam.qrCode(for: url, size: 168)
            tooLong = qr == nil
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
