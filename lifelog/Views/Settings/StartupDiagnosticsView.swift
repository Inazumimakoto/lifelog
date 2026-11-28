import SwiftUI
import UIKit

/// TestFlight / Debug diagnostic sheet to inspect real-device cold launch timings.
struct StartupDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reportText: String = ""
    @State private var copied = false

    private let profiler = StartupProfiler.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryGrid

                    Button {
                        UIPasteboard.general.string = reportText
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "コピーしました" : "レポートをコピー", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("※ タスクを一度スワイプ終了してからコールド起動した直後に開くと正確な数値になります。日記本文や予定タイトルなどの個人内容は含まれません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(reportText)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding()
            }
            .navigationTitle("起動時間レポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                reportText = profiler.formattedReport()
            }
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricTile("起動→操作可能", value: profiler.totalInteractiveSummary)
            metricTile("OS + dyld", value: formatMs(profiler.preMainMs))
            metricTile("DB open + init", value: formatMs(profiler.storeInitTotalMs))
            metricTile("UI初回構築", value: formatMs(profiler.uiFirstFrameMs))
        }
    }

    private func metricTile(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced).bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatMs(_ ms: Double?) -> String {
        guard let ms else { return "-" }
        return String(format: "%.0f ms", ms)
    }
}
