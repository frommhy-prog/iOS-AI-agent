import SwiftUI
import FoundationModels

// 设置：主题只保留「跟随系统 / 浅色 / 深色」，默认跟随系统
struct AppSettingsView: View {
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("saveHistory") private var saveHistory = true
    @AppStorage("style") private var style = 0
    @AppStorage("autoSend") private var autoSend = false
    @AppStorage("liveOn") private var liveOn = true
    @State private var exportURL: URL?
    @State private var confirmChats = false
    @State private var confirmKB = false
    @State private var showClock = false
    @State private var copied = false

    private var modelStatus: String {
        switch SystemLanguageModel.default.availability {
        case .available: return "可用"
        case .unavailable(let r): return Agent.unavailableText("\(r)")
        @unknown default: return "未知"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: $appearance) {
                        Text("跟随系统").tag(0)
                        Text("浅色").tag(1)
                        Text("深色").tag(2)
                    }
                    .pickerStyle(.segmented)
                }
                Section("对话") {
                    Toggle("保存对话记录", isOn: $saveHistory)
                    Picker("回答风格", selection: $style) {
                        Text("简洁").tag(0)
                        Text("详细").tag(1)
                    }
                    Toggle("语音说完后自动发送", isOn: $autoSend)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本机模型")
                        Text(modelStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("闹钟与连接") {
                    Button { showClock = true } label: { Label("系统时钟闹钟与自检", systemImage: "alarm") }
                }
                Section("灵动岛与实时活动") {
                    Toggle("在灵动岛显示思考、闹钟与任务倒计时", isOn: $liveOn)
                }
                Section("权限") {
                    Button { openSettings() } label: { Label("通知、闹钟、日历、麦克风等权限", systemImage: "gearshape") }
                }
                Section("数据") {
                    if let u = exportURL {
                        ShareLink(item: u) { Label("导出全部对话", systemImage: "square.and.arrow.up") }
                    }
                    Button(role: .destructive) { confirmChats = true } label: { Label("清空所有对话", systemImage: "trash") }
                    Button(role: .destructive) { confirmKB = true } label: { Label("清空知识库", systemImage: "trash") }
                }
                Section("关于") {
                    HStack {
                        LogoMark(size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TSTZ Bot").font(.headline)
                            Text("版本 0.5").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    HStack {
                        Text("开发者微信")
                        Spacer()
                        Text("TSTZ-M").foregroundStyle(.secondary)
                        Button {
                            UIPasteboard.general.string = "TSTZ-M"
                            copied = true
                        } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { exportURL = exportAll() }
            .sheet(isPresented: $showClock) { ClockSetupView().presentationBackground(Brand.bg) }
            .confirmationDialog("清空所有对话？此操作无法撤销", isPresented: $confirmChats, titleVisibility: .visible) {
                Button("清空", role: .destructive) { Agent.shared.clearAll() }
            }
            .confirmationDialog("清空知识库？此操作无法撤销", isPresented: $confirmKB, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    DB.shared.run("DELETE FROM chunk")
                    DB.shared.run("DELETE FROM doc")
                }
            }
        }
    }

    func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }

    func exportAll() -> URL? {
        var s = "# TSTZ Bot 对话记录\n\n"
        for c in DB.shared.rows("SELECT id,title,ts FROM conv ORDER BY ts") {
            s += "## " + c.s("title") + "（" + Sys.fmt(Date(timeIntervalSince1970: c.d("ts"))) + "）\n\n"
            for m in DB.shared.rows("SELECT role,text FROM msg WHERE conv=? ORDER BY id", [c.i("id")]) {
                s += (m.s("role") == "user" ? "**我**：" : "**TSTZ Bot**：") + m.s("text") + "\n\n"
            }
        }
        let u = Store.dir("Outputs").appendingPathComponent("TSTZ Bot 对话记录.md")
        try? s.write(to: u, atomically: true, encoding: .utf8)
        return u
    }
}
