import SwiftUI
import UIKit
import ImageIO
import Photos

extension Files {
    // 把数据落地成文件：依次尝试「文档/Inbox → 缓存 → 临时目录」，写完核对大小；失败会带回具体错误码
    static func save(_ data: Data, name: String) -> (url: URL?, error: String) {
        guard !data.isEmpty else { return (nil, "数据为空") }
        let fm = FileManager.default
        let dirs: [URL] = [
            Store.dir("Inbox"),
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory,
            fm.temporaryDirectory
        ]
        var errs: [String] = []
        for d in dirs {
            let u = d.appendingPathComponent(name)
            do {
                try fm.createDirectory(at: d, withIntermediateDirectories: true)
                try data.write(to: u, options: .atomic)
                if (size(u) ?? 0) == Int64(data.count) { return (u, "") }
                errs.append("大小不符")
            } catch {
                let n = error as NSError
                errs.append("\(n.domain) \(n.code)")
            }
        }
        return (nil, "写入失败 " + errs.joined(separator: " / "))
    }

    // 任意图片数据（HEIC、PNG、JPEG…）→ 方向正确、长边不超过 maxPixel 的 JPEG，直接在内存里完成
    static func jpegData(fromImageData raw: Data, maxPixel: Int = 3072) -> Data? {
        if let s = CGImageSourceCreateWithData(raw as CFData, nil) {
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(s, 0, opts as CFDictionary),
               let d = UIImage(cgImage: cg).jpegData(compressionQuality: 0.92) { return d }
        }
        if let ui = UIImage(data: raw), let d = jpeg(from: ui) { return d }
        return nil
    }

    static func stampText() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMdd-HHmmss"
        return f.string(from: Date())
    }
}

// 从相册资源取一张图：原图数据 → 高质量渲染图 → 资源数据，三层兜底（都允许从 iCloud 下载）
enum AssetLoader {
    static func jpeg(_ a: PHAsset) async -> (Data?, String) {
        var errs: [String] = []

        let r1 = await originalData(a)
        if let raw = r1.0 {
            if let j = Files.jpegData(fromImageData: raw) { return (j, "") }
            errs.append("原图无法解码")
        } else {
            errs.append(r1.1)
        }

        let r2 = await rendered(a)
        if let img = r2.0 {
            if let j = Files.jpeg(from: img) { return (j, "") }
            errs.append("渲染图无法编码")
        } else {
            errs.append(r2.1)
        }

        let r3 = await resourceData(a)
        if let raw = r3.0 {
            if let j = Files.jpegData(fromImageData: raw) { return (j, "") }
            errs.append("资源无法解码")
        } else {
            errs.append(r3.1)
        }
        return (nil, errs.joined(separator: " | "))
    }

    private static func originalData(_ a: PHAsset) async -> (Data?, String) {
        await withCheckedContinuation { (cont: CheckedContinuation<(Data?, String), Never>) in
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            o.version = .current
            var done = false
            PHImageManager.default().requestImageDataAndOrientation(for: a, options: o) { data, _, _, info in
                if done { return }
                done = true
                if let data, !data.isEmpty {
                    cont.resume(returning: (data, ""))
                } else {
                    let e = (info?[PHImageErrorKey] as? NSError).map { "原图 \($0.domain) \($0.code)" } ?? "原图为空"
                    cont.resume(returning: (nil, e))
                }
            }
        }
    }

    private static func rendered(_ a: PHAsset) async -> (UIImage?, String) {
        await withCheckedContinuation { (cont: CheckedContinuation<(UIImage?, String), Never>) in
            let o = PHImageRequestOptions()
            o.deliveryMode = .highQualityFormat
            o.resizeMode = .fast
            o.isNetworkAccessAllowed = true
            var done = false
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 3072, height: 3072), contentMode: .aspectFit, options: o) { img, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                if done { return }
                done = true
                if let img {
                    cont.resume(returning: (img, ""))
                } else {
                    let e = (info?[PHImageErrorKey] as? NSError).map { "渲染 \($0.domain) \($0.code)" } ?? "渲染无图"
                    cont.resume(returning: (nil, e))
                }
            }
        }
    }

    private static func resourceData(_ a: PHAsset) async -> (Data?, String) {
        let all = PHAssetResource.assetResources(for: a)
        guard let res = all.first(where: { $0.type == .fullSizePhoto }) ?? all.first(where: { $0.type == .photo }) ?? all.first else {
            return (nil, "没有资源")
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<(Data?, String), Never>) in
            let o = PHAssetResourceRequestOptions()
            o.isNetworkAccessAllowed = true
            var buf = Data()
            PHAssetResourceManager.default().requestData(for: res, options: o, dataReceivedHandler: { chunk in
                buf.append(chunk)
            }, completionHandler: { err in
                if let err {
                    let n = err as NSError
                    cont.resume(returning: (nil, "资源 \(n.domain) \(n.code)"))
                } else if buf.isEmpty {
                    cont.resume(returning: (nil, "资源为空"))
                } else {
                    cont.resume(returning: (buf, ""))
                }
            })
        }
    }
}
