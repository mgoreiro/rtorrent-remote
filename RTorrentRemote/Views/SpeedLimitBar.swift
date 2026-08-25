import SwiftUI

struct SpeedStatusBar: View {
    @ObservedObject var viewModel: TorrentListViewModel

    var body: some View {
        HStack(spacing: 16) {
            Label(Formatters.rate(viewModel.globalDownRate), systemImage: "arrow.down.circle")
            Label(Formatters.rate(viewModel.globalUpRate), systemImage: "arrow.up.circle")
            Spacer()
            Text("\(viewModel.torrents.count) torrents")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
