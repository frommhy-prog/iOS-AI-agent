import SwiftUI
import Photos
import UIKit

extension Files {
    // UIImage → 方向正确、长边不超过 maxPixel 的 JPEG（用绘制重新生成，不依赖文件解码）
    static func jpeg(from img: UIImage, maxPixel: CGFloat = 3072) -> Data? {
        let pw = img.size.width * img.scale
        let ph = img.size.height * img.scale
        guard pw > 0, ph > 0 else { return nil }
        let k = min(1, maxPixel / max(pw, ph))
        let target = CGSize(width: max(1, (pw * k).rounded()), height: max(1, (ph * k).rounded()))
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        let r = UIGraphicsImageRenderer(size: target, format: f)
        return r.jpegData(withCompressionQuality: 0.92) { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

extension UIApplication {
    // 当前最上层的视图控制器（用于弹出系统的「管理所选照片」）
    var topVC: UIViewController? {
        let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        var vc = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}

private struct AssetThumb: View {
    let asset: PHAsset
    let order: Int?
    @State private var img: UIImage?

    var body: some View {
        Color(.tertiarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img { Image(uiImage: img).resizable().scaledToFill() }
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                ZStack {
                    Circle().fill(order == nil ? Color.black.opacity(0.25) : Brand.accent)
                    Circle().stroke(Color.white, lineWidth: 1.5)
                    if let order {
                        Text("\(order)").font(.caption2.bold()).foregroundStyle(Brand.onAccent)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(5)
            }
            .contentShape(Rectangle())
            .onAppear {
                guard img == nil else { return }
                let o = PHImageRequestOptions()
                o.deliveryMode = .opportunistic
                o.resizeMode = .fast
                o.isNetworkAccessAllowed = true
                PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 260, height: 260), contentMode: .aspectFill, options: o) { i, _ in
                    if let i { DispatchQueue.main.async { img = i } }
                }
            }
    }
}

// 自带相册：申请「全部照片」权限，列出整个相册，多选后转成标准 JPEG。权限被拒绝时可改用系统选择器。
struct GalleryPicker: View {
    var onPick: ([URL]) -> Void
    var onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var assets: [PHAsset] = []
    @State private var selected: [String] = []
    @State private var working = false
    @State private var useSystem = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(selected.isEmpty ? "选择照片" : "已选 \(selected.count) 张")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                    if !useSystem {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(working ? "处理中…" : "添加") { confirm() }.disabled(selected.isEmpty || working)
                        }
                    }
                }
        }
        .presentationBackground(Brand.bg)
        .task { await prepare() }
    }

    @ViewBuilder
    var content: some View {
        if useSystem {
            PhotoPicker(onPick: { urls in
                onPick(urls)
                dismiss()
            }, onError: onError)
        } else {
            switch status {
            case .authorized, .limited:
                grid
            case .denied, .restricted:
                denied
            default:
                ProgressView("正在请求相册权限…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    var grid: some View {
        ScrollView {
            if status == .limited {
                VStack(spacing: 8) {
                    Text("现在只授权了部分照片，想看到全部请改为「所有照片」").font(.footnote).foregroundStyle(Brand.sub)
                    HStack(spacing: 12) {
                        Button("选择更多照片") {
                            if let vc = UIApplication.shared.topVC {
                                PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: vc) { _ in reload() }
                            }
                        }
                        Button("去设置改为全部") { openSettings() }
                    }
                    .font(.footnote.weight(.semibold))
                }
                .padding(12)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                ForEach(assets, id: \.localIdentifier) { a in
                    AssetThumb(asset: a, order: selected.firstIndex(of: a.localIdentifier).map { $0 + 1 })
                        .onTapGesture { toggle(a) }
                }
            }
        }
    }

    var denied: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(Brand.sub)
            Text("没有相册权限").font(.headline)
            Text("到 设置 → TSTZ Bot → 照片，选择「所有照片」，就能看到整个相册。").font(.subheadline).foregroundStyle(Brand.sub).multilineTextAlignment(.center)
            Button("打开设置") { openSettings() }.buttonStyle(.borderedProminent)
            Button("改用系统选择器（无需授权）") { useSystem = true }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }

    func prepare() async {
        var s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if s == .notDetermined { s = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        status = s
        if s == .authorized || s == .limited { reload() }
    }

    func reload() {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.fetchLimit = 4000
        let r = PHAsset.fetchAssets(with: .image, options: o)
        var list: [PHAsset] = []
        r.enumerateObjects { a, _, _ in list.append(a) }
        assets = list
    }

    func toggle(_ a: PHAsset) {
        let id = a.localIdentifier
        if let i = selected.firstIndex(of: id) {
            selected.remove(at: i)
        } else if selected.count < 9 {
            selected.append(id)
        }
    }

    func confirm() {
        let picked = selected.compactMap { id in assets.first(where: { $0.localIdentifier == id }) }
        working = true
        Task {
            var urls: [URL] = []
            var err = ""
            let stamp = Store.stamped("照片", "jpg").deletingPathExtension().lastPathComponent
            for (i, a) in picked.enumerated() {
                let r = await Self.load(a)
                if let data = r.0 {
                    let dst = Store.dir("Inbox").appendingPathComponent("\(stamp)-\(i + 1).jpg")
                    if (try? data.write(to: dst)) != nil, Files.readable(dst) { urls.append(dst) } else { err = "保存失败" }
                } else {
                    err = r.1
                }
            }
            working = false
            if urls.isEmpty { onError("图片读取失败（\(err)）。可以先在相册里点开这张图让它下载完整，再试一次。") }
            onPick(urls)
            dismiss()
        }
    }

    // 取一张高质量图（允许从 iCloud 下载），返回 JPEG 数据或错误码
    static func load(_ a: PHAsset) async -> (Data?, String) {
        await withCheckedContinuation { cont in
            let o = PHImageRequestOptions()
            o.deliveryMode = .highQualityFormat
            o.resizeMode = .fast
            o.isNetworkAccessAllowed = true
            o.isSynchronous = false
            var finished = false
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 3072, height: 3072), contentMode: .aspectFit, options: o) { img, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                if finished { return }
                finished = true
                if let img, let d = Files.jpeg(from: img) {
                    cont.resume(returning: (d, ""))
                } else {
                    let e = (info?[PHImageErrorKey] as? NSError).map { "\($0.domain) \($0.code)" } ?? "没有返回图片"
                    cont.resume(returning: (nil, e))
                }
            }
        }
    }
}

// 拍照：拍完直接生成标准 JPEG，失败会说明原因
struct CameraPicker: UIViewControllerRepresentable {
    var onPick: (URL?, String?) -> Void

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
            guard let img = info[.originalImage] as? UIImage else {
                parent.onPick(nil, "没有拿到照片")
                return
            }
            guard let d = Files.jpeg(from: img) else {
                parent.onPick(nil, "照片转换失败")
                return
            }
            let dst = Store.stamped("拍照", "jpg")
            do {
                try d.write(to: dst)
                parent.onPick(dst, nil)
            } catch {
                parent.onPick(nil, "照片保存失败：\(error.localizedDescription)")
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onPick(nil, nil) }
    }
}
