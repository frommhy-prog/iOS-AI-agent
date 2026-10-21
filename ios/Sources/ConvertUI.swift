import SwiftUI
import PhotosUI
import QuickLook
import ImageIO
import UniformTypeIdentifiers

// 相册里的视频：系统选择器给出的临时文件复制进 Inbox
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { m in
            SentTransferredFile(m.url)
        } importing: { received in
            let e = received.file.pathExtension.lowercased()
            let ext = e.isEmpty ? "mov" : e
            let dst = Store.dir("Inbox").appendingPathComponent("视频-\(Files.stampText()).\(ext)")
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return PickedMovie(url: dst)
        }
    }
}

// MARK: 文件转换：可以从相册选照片或视频，也可以从「文件」App 选
struct ConvertView: View {
    @State private var file: URL?
    @State private var showPick = false
    @State private var showPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var loading = false
    @State private var target = ""
    @State private var outs: [URL] = []
    @State private var busy = false
    @State private var err = ""
    @State private var preview: URL?

    static let names: [String: String] = [
        "jpg": "JPG 图片", "png": "PNG 图片", "heic": "HEIC 图片", "pdf": "PDF", "tiff": "TIFF 图片", "gif": "GIF 图片", "bmp": "BMP 图片",
        "txt": "文字", "csv": "CSV 表格", "json": "JSON", "md": "Markdown", "html": "网页", "tsv": "TSV 表格",
        "mp4": "MP4 视频", "mov": "MOV 视频", "m4a": "音频", "compress": "压缩视频"
    ]

    var targets: [String] {
        guard let f = file else { return [] }
        let e = f.pathExtension.lowercased()
        if Convert.imgExt.contains(e) { return ["jpg", "png", "heic", "pdf", "tiff", "gif", "bmp", "txt"] }
        if e == "pdf" { return ["png", "jpg", "txt"] }
        if Convert.vidExt.contains(e) { return ["mp4", "mov", "m4a", "compress", "jpg"] }
        return ["csv", "json", "md", "html", "txt", "tsv", "pdf"]
    }

    var body: some View {
        List {
            Section {
                Button { showPhotos = true } label: { Label("从相册选择照片或视频", systemImage: "photo.on.rectangle") }
                Button { showPick = true } label: { Label("从「文件」App 选择", systemImage: "folder") }
                if loading {
                    HStack(spacing: 8) { ProgressView(); Text("正在读取…").foregroundStyle(.secondary) }
                } else if let f = file {
                    Label("已选择：" + f.lastPathComponent, systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                }
            }
            if !targets.isEmpty {
                Section("转换成") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(targets, id: \.self) { t in
                            Button { target = t } label: {
                                Text(Self.names[t] ?? t).font(.subheadline)
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .background(target == t ? Brand.accent : Color(.tertiarySystemFill))
                                    .foregroundStyle(target == t ? Brand.onAccent : Color.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    Button { convert() } label: {
                        HStack { if busy { ProgressView() }; Text(busy ? "转换中…" : "开始转换").frame(maxWidth: .infinity) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || target.isEmpty)
                    .listRowBackground(Color.clear)
                }
            }
            if !err.isEmpty { Section { Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            if !outs.isEmpty {
                Section("转换结果") {
                    ForEach(outs, id: \.self) { u in
                        VStack(alignment: .leading, spacing: 8) {
                            FileCard(url: u, preview: $preview)
                            if Convert.imgExt.contains(u.pathExtension.lowercased()) || Convert.vidExt.contains(u.pathExtension.lowercased()) {
                                Button("存入相册") { saveToPhotos(u) }
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                }
            }
            Section {
                Text("支持图片、PDF、表格（CSV、JSON、Markdown、网页）、文本、视频互相转换，也能识别图片中的文字。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("文件转换")
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($preview)
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 1, matching: .any(of: [.images, .videos]))
        .onChange(of: photoItems) { _, items in
            guard let it = items.first else { return }
            photoItems = []
            Task { await loadPicked(it) }
        }
        .fileImporter(isPresented: $showPick, allowedContentTypes: [.item]) { r in
            guard let u = try? r.get() else { return }
            let res = Files.importFile(u)
            if let c = res.url { setFile(c) } else { err = res.error ?? "文件读取失败" }
        }
    }

    func setFile(_ u: URL) {
        file = u
        outs = []
        err = ""
        target = targets.first ?? ""
    }

    // 相册选中的照片或视频 → 落地成文件
    func loadPicked(_ item: PhotosPickerItem) async {
        loading = true
        err = ""
        defer { loading = false }
        let isVideo = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        if isVideo {
            do {
                if let m = try await item.loadTransferable(type: PickedMovie.self) { setFile(m.url) } else { err = "视频读取失败，请换一个再试" }
            } catch {
                err = "视频读取失败：\(error.localizedDescription)"
            }
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { err = "图片读取失败，请换一张再试"; return }
            let stamp = Files.stampText()
            if let ext = Self.imageExt(data) {
                let s = Files.save(data, name: "照片-\(stamp).\(ext)")
                if let u = s.url { setFile(u) } else { err = "图片保存失败（\(s.error)）" }
            } else if let j = Files.jpegData(fromImageData: data) {
                let s = Files.save(j, name: "照片-\(stamp).jpg")
                if let u = s.url { setFile(u) } else { err = "图片保存失败（\(s.error)）" }
            } else {
                err = "这张图片的格式无法识别"
            }
        } catch {
            err = "图片读取失败：\(error.localizedDescription)"
        }
    }

    // 按内容判断格式；不在支持列表里返回 nil（会改存为 JPEG）
    static func imageExt(_ data: Data) -> String? {
        guard let s = CGImageSourceCreateWithData(data as CFData, nil),
              let t = CGImageSourceGetType(s),
              let ut = UTType(t as String),
              let e = ut.preferredFilenameExtension else { return nil }
        let x = e.lowercased() == "jpeg" ? "jpg" : e.lowercased()
        return Convert.imgExt.contains(x) ? x : nil
    }

    func convert() {
        guard let f = file else { return }
        busy = true
        err = ""
        Task {
            do { outs = try await Convert.run(f, to: target) } catch { err = error.localizedDescription }
            busy = false
        }
    }

    func saveToPhotos(_ u: URL) {
        if let img = UIImage(contentsOfFile: u.path) { UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil) }
        else if Convert.vidExt.contains(u.pathExtension.lowercased()) { UISaveVideoAtPathToSavedPhotosAlbum(u.path, nil, nil, nil) }
    }
}
