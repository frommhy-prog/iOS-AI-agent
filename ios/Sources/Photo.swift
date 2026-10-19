import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private final class PickBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URL] = []
    func add(_ u: URL) { lock.lock(); items.append(u); lock.unlock() }
    var all: [URL] { lock.lock(); defer { lock.unlock() }; return items.sorted { $0.path < $1.path } }
}

// 相册选图：直接取原始文件并转成标准 JPEG，避免读不出来
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
                r.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { src, _ in
                    defer { group.leave() }
                    guard let src, let d = try? Data(contentsOf: src), !d.isEmpty,
                          let ui = UIImage(data: d), let jpg = ui.jpegData(compressionQuality: 0.92) else { return }
                    let dst = inbox.appendingPathComponent("\(stamp)-\(i + 1).jpg")
                    if (try? jpg.write(to: dst)) != nil { box.add(dst) }
                }
            }
            group.notify(queue: .main) {
                let urls = box.all
                if urls.isEmpty { self.parent.onError("图片读取失败。如果照片在 iCloud 里，请先在相册里下载原图，或换一张试试。") }
                self.parent.onPick(urls)
            }
        }
    }
}
