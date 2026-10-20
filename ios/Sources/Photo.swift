import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private final class PickBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URL] = []
    func add(_ u: URL) { lock.lock(); items.append(u); lock.unlock() }
    var all: [URL] { lock.lock(); defer { lock.unlock() }; return items.sorted { $0.path < $1.path } }
}

// 相册选图：取原始文件，用 ImageIO 转成方向正确的标准 JPEG（HEIC、竖拍、超大图都能读），并逐张校验
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
                    guard let src, let jpg = Files.normalizedJPEG(from: src) else { return }
                    let dst = inbox.appendingPathComponent("\(stamp)-\(i + 1).jpg")
                    if (try? jpg.write(to: dst)) != nil, Files.readable(dst) { box.add(dst) }
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

// 拍照：拍完同样转成方向正确的 JPEG
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            var out: URL?
            if let img = info[.originalImage] as? UIImage, let d = img.jpegData(compressionQuality: 0.95) {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try? d.write(to: tmp)
                if let jpg = Files.normalizedJPEG(from: tmp) {
                    let dst = Store.stamped("拍照", "jpg")
                    if (try? jpg.write(to: dst)) != nil { out = dst }
                }
                try? FileManager.default.removeItem(at: tmp)
            }
            parent.onPick(out)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onPick(nil) }
    }
}
