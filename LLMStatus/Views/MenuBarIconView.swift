import SwiftUI

/// Displays the cloud logo tinted by service status. Reusable in popover header and elsewhere.
struct MenuBarIconView: View {
    let status: ServiceStatus
    var size: CGFloat = 18

    var body: some View {
        if let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "pdf"),
           let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: size)
                .foregroundStyle(status.color)
        } else {
            Image(systemName: status.sfSymbol)
                .foregroundStyle(status.color)
        }
    }
}
