import SwiftUI
import EventKit
import Photos
import PhotosUI
import FoundationModels

// 今日回顾：iOS 不允许 App 读取「屏幕使用时间」和其他 App 的通知，所以这里只汇总本机允许读取的数据，
// 再加上用户导入的屏幕使用时间 / 通知截图（端侧文字识别），由本机模型写成当天总结。
@MainActor
enum Digest {
    static func hm(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    // 读取今天本机能读到的数据；没有授权的项目直接略过
    static func collect() async -> [String] {
        var out: [String] = []
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let store = EKEventStore()

        if let ok = try? await store.requestFullAccessToEvents(), ok {
            let evs = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
                .sorted { $0.startDate < $1.startDate }
            if evs.isEmpty {
                out.append("日历：今天没有日程")
            } else {
                let list = evs.prefix(10).map { (($0.isAllDay ? "全天" : hm($0.startDate)) + " " + ($0.title ?? "")) }
                out.append("日历：共 \(evs.count) 项：" + list.joined(separator: "；"))
            }
        }

        if let ok = try? await store.requestFullAccessToReminders(), ok {
            let pred = store.predicateForReminders(in: nil)
            let all: [EKReminder] = await withCheckedContinuation { (c: CheckedContinuation<[EKReminder], Never>) in
                store.fetchReminders(matching: pred) { c.resume(returning: $0 ?? []) }
            }
            let todo = all.filter { r in
                guard !r.isCompleted, let comps = r.dueDateComponents, let d = cal.date(from: comps) else { return false }
                return d < end
            }
            let done = all.filter { r in
                guard r.isCompleted, let d = r.completionDate else { return false }
                return d >= start
            }
            var s = "提醒事项：今天及逾期未完成 \(todo.count) 项"
            if !todo.isEmpty { s += "（" + todo.prefix(8).map { $0.title ?? "" }.joined(separator: "、") + "）" }
            s += "；今天已完成 \(done.count) 项"
            if !done.isEmpty { s += "（" + done.prefix(8).map { $0.title ?? "" }.joined(separator: "、") + "）" }
            out.append(s)
        }

        let st = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if st == .authorized || st == .limited {
            let o = PHFetchOptions()
            o.predicate = NSPredicate(format: "creationDate >= %@", start as NSDate)
            o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let r = PHAsset.fetchAssets(with: o)
            if r.count > 0 {
                var photos = 0
                var videos = 0
                r.enumerateObjects { a, i, stop in
                    if a.mediaType == .video { videos += 1 } else { photos += 1 }
                    if i >= 999 { stop.pointee = true }
                }
                var s = "相册：今天拍了 \(photos) 张照片"
                if videos > 0 { s += "、\(videos) 段视频" }
                if let f = r.firstObject?.creationDate, let l = r.lastObject?.creationDate { s += "，时间 \(hm(f)) 到 \(hm(l))" }
                out.append(s)
            } else {
                out.append("相册：今天没有新照片")
            }
        }

        let ts = start.timeIntervalSince1970
        let asked = DB.shared.rows("SELECT COUNT(*) AS n FROM msg WHERE role='user' AND ts>=?", [ts]).first?.i("n") ?? 0
        out.append("助理：今天和助理对话 \(asked) 次")

        let tasks = Tasks.list().filter { $0.d("due") >= ts && $0.d("due") < ts + 86400 }
        if !tasks.isEmpty {
            out.append("定时任务：今天有 \(tasks.count) 个：" + tasks.prefix(6).map { $0.s("title") }.joined(separator: "、"))
        }
        let alarms = Tasks.alarms().filter { $0.d("due") >= ts && $0.d("due") < ts + 86400 }
        if !alarms.isEmpty {
            out.append("闹钟：今天有 \(alarms.count) 个：" + alarms.prefix(6).map { Sys.plainLabel($0.s("label")) + " " + hm(Date(timeIntervalSince1970: $0.d("due"))) }.joined(separator: "、"))
        }
        return out
    }

    // 截图 → 文字（端侧识别，不联网）
    static func readShot(_ data: Data) async -> String {
        let s = Files.save(data, name: "回顾截图-\(UUID().uuidString.prefix(6)).jpg")
        guard let u = s.url else { return "" }
        let text = await Task.detached { OCR.text(u) }.value
        try? FileManager.default.removeItem(at: u)
        return String(text.prefix(1500))
    }

    static func summarize(facts: [String], screens: [String], onUpdate: @escaping (String) -> Void) async -> String {
        switch SystemLanguageModel.default.availability {
        case .available: break
        case .unavailable(let r): return Agent.unavailableText("\(r)")
        @unknown default: break
        }
        var prompt = "今天是 " + Sys.fmtFull(Date()) + "。以下是今天的资料：\n" + facts.joined(separator: "\n")
        if !screens.isEmpty {
            let joined = screens.joined(separator: "\n---\n")
            prompt += "\n\n以下是用户导入的屏幕使用时间或通知截图中识别出的文字（可能有错字）：\n" + String(joined.prefix(1500))
        }
        let ins = "你是用户的个人助理。根据给出的当天资料写一份中文每日回顾：先用一句话概括今天，再分三段列出「做了什么」「时间花在哪（有截图数据才写）」「明天要留意」，每段最多三条。只依据资料，资料里没有的内容不要编造。总共不超过 300 字。"
        let session = LanguageModelSession(instructions: ins)
        var last = ""
        do {
            for try await snap in session.streamResponse(to: prompt) {
                last = snap.content
                onUpdate(last)
            }
        } catch {
            return last.isEmpty ? "这次没能生成（\(String("\(error)".prefix(80)))），请再试一次。" : last
        }
        return last.isEmpty ? "模型没有返回内容，请再试一次。" : last
    }
}

struct DigestView: View {
    @State private var facts: [String] = []
    @State private var loadingFacts = false
    @State private var showPicker = false
    @State private var items: [PhotosPickerItem] = []
    @State private var screens: [String] = []
    @State private var reading = false
    @State private var result = ""
    @State private var busy = false
    @State private var saved = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("汇总今天本机允许读取的日历、提醒事项、相册、任务和对话，再由本机模型写成一份总结。")
                        .font(.footnote).foregroundStyle(Brand.sub)
                }
                Section("今天自动读取到的") {
                    if loadingFacts { HStack(spacing: 8) { ProgressView(); Text("正在读取…").foregroundStyle(Brand.sub) } }
                    ForEach(facts, id: \.self) { Text($0).font(.subheadline) }
                    Button { Task { await refresh() } } label: { Label("重新读取", systemImage: "arrow.clockwise") }.disabled(loadingFacts)
                }
                Section("屏幕使用时间与通知") {
                    Text("iOS 不允许任何 App 直接读取屏幕使用时间和其他 App 的通知。办法：在「设置 → 屏幕使用时间 → 查看所有活动」截图，或截一张通知中心，在这里导入，由本机识别文字后一起总结。")
                        .font(.footnote).foregroundStyle(Brand.sub)
                    Button { showPicker = true } label: { Label("导入截图", systemImage: "photo.badge.plus") }.disabled(reading)
                    if reading { HStack(spacing: 8) { ProgressView(); Text("正在识别文字…").foregroundStyle(Brand.sub) } }
                    if !screens.isEmpty {
                        HStack {
                            Text("已识别 \(screens.count) 张截图").font(.subheadline)
                            Spacer()
                            Button("清除") { screens = [] }.buttonStyle(.borderless)
                        }
                    }
                }
                Section {
                    Button { generate() } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView() }
                            Text(busy ? "正在总结…" : "生成今日总结").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || loadingFacts)
                    .listRowBackground(Color.clear)
                }
                if !result.isEmpty {
                    Section("今日回顾") {
                        Text(result).textSelection(.enabled)
                        ShareLink(item: result) { Label("分享", systemImage: "square.and.arrow.up") }
                        Button { save() } label: { Label(saved ? "已存入知识库" : "存入知识库", systemImage: "books.vertical") }.disabled(saved || busy)
                    }
                }
            }
            .navigationTitle("今日回顾")
            .navigationBarTitleDisplayMode(.inline)
            .photosPicker(isPresented: $showPicker, selection: $items, maxSelectionCount: 6, matching: .images)
            .onChange(of: items) { _, new in
                guard !new.isEmpty else { return }
                let picked = new
                items = []
                Task { await importShots(picked) }
            }
            .task { await refresh() }
        }
    }

    func refresh() async {
        loadingFacts = true
        facts = await Digest.collect()
        loadingFacts = false
    }

    func importShots(_ picked: [PhotosPickerItem]) async {
        reading = true
        for it in picked {
            if let d = try? await it.loadTransferable(type: Data.self), let j = Files.jpegData(fromImageData: d) {
                let t = await Digest.readShot(j)
                if !t.isEmpty { screens.append(t) }
            }
        }
        reading = false
    }

    func generate() {
        busy = true
        result = ""
        saved = false
        Task {
            if facts.isEmpty { facts = await Digest.collect() }
            result = await Digest.summarize(facts: facts, screens: screens) { result = $0 }
            busy = false
        }
    }

    func save() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        _ = KB.shared.upsert("回顾 " + f.string(from: Date()), result)
        saved = true
    }
}
