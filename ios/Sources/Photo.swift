import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private final class PickBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URL] = []
    private var errs: [String] = []
    func add(_ u: URL) { lock.lock(); items.append(u); lock.unlock() }
    func fail(_ e: String) { lock.lock(); errs.append(e); lock.unlock() }
    var all: [URL] { lock.lock(); defer { lock.unlock() }; return items.sorted { $0.path < $1.path } }
    var firstError: String { lock.lock(); defer { lock.unlock() }; return errs.first ?? "" }
}

// 系统选择器的取图：依次尝试 JPEG 表示 → 其他图片表示 → 数据表示 → UIImage 对象，任何一层成功即可；全失败会带回具体错误码
enum PhotoLoader {
    static func load(_ p: NSItemProvider, done: @escaping (Data?, String) -> Void) {
        var ids = p.registeredTypeIdentifiers.filter { UTType($0)?.conforms(to: .image) == true }
        if let j = ids.firstIndex(of: UTType.jpeg.identifier) { ids.insert(ids.remove(at: j), at: 0) }
        if ids.isEmpty { ids = [UTType.image.identifier] }
        tryFile(p, ids, 0, "", done)
    }

    static func desc(_ e: Error) -> String {
        let n = e as NSError
        return "\(n.domain) \(n.code)"
    }

    private static func tryFile(_ p: NSItemProvider, _ ids: [String], _ i: Int, _ err: String, _ done: @escaping (Data?, String) -> Void) {
        guard i < ids.count else { tryData(p, err, done); return }
        _ = p.loadFileRepresentation(forTypeIdentifier: ids[i]) { url, e in
            if let url, let d = Files.normalizedJPEG(from: url) { done(d, ""); return }
            let why = e.map { desc($0) } ?? "文件无法解码"
            tryFile(p, ids, i + 1, err + "[\(ids[i]) \(why)]", done)
        }
    }

    private static func tryData(_ p: NSItemProvider, _ err: String, _ done: @escaping (Data?, String) -> Void) {
        _ = p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, e in
            if let data, !data.isEmpty {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try? data.write(to: tmp)
                let d = Files.normalizedJPEG(from: tmp)
                try? FileManager.default.removeItem(at: tmp)
                if let d { done(d, ""); return }
            }
            tryObject(p, err + "[数据 \(e.map { desc($0) } ?? "无法解码")]", done)
        }
    }

    private static func tryObject(_ p: NSItemProvider, _ err: String, _ done: @escaping (Data?, String) -> Void) {
        guard p.canLoadObject(ofClass: UIImage.self) else { done(nil, err + "[不能作为图片读取]"); return }
        _ = p.loadObject(ofClass: UIImage.self) { obj, e in
            if let ui = obj as? UIImage, let d = Files.jpeg(from: ui) { done(d, ""); return }
            done(nil, err + "[对象 \(e.map { desc($0) } ?? "无法解码")]")
        }
    }
}

// 系统相册选择器（不需要相册权限）：作为「全部相册」授权被拒绝时的备用方案
struct PhotoPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var c = PHPickerConfiguration()
        c.filter = .images
        c.selectionLimit = 5
        let p = PHPickerViewController(configuration: c)
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker
        init(_ p: PhotoPicker) { parent = p }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if results.isEmpty {
                DispatchQueue.main.async { self.parent.onPick([]) }
                return
            }
            let box = PickBox()
            let group = DispatchGroup()
            let stamp = Store.stamped("照片", "jpg").deletingPathExtension().lastPathComponent
            let inbox = Store.dir("Inbox")
            for (i, r) in results.enumerated() {
                group.enter()
                PhotoLoader.load(r.itemProvider) { data, err in
                    defer { group.leave() }
                    guard let data else { box.fail(err); return }
                    let dst = inbox.appendingPathComponent("\(stamp)-\(i + 1).jpg")
                    if (try? data.write(to: dst)) != nil, Files.readable(dst) {
                        box.add(dst)
                    } else {
                        box.fail("写入后无法读取")
                    }
                }
            }
            group.notify(queue: .main) {
                let urls = box.all
                if urls.isEmpty {
                    self.parent.onError("图片读取失败 \(String(box.firstError.prefix(160)))。")
                }
                self.parent.onPick(urls)
            }
        }
    }
}
